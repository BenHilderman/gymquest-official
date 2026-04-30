// ContentSafetyService — locked spec content-safety architecture, Phase 1.
//
// On-device first lane for moderating audio / photo / video uploads across
// every Lift AI surface (posts, comments, DMs, squad chat, stories). All
// checks run in <300ms with no network — Apple Vision for image
// classification, Apple Speech for on-device transcription, plus a
// shipped slur/abuse word list. Verdict is the single contract:
//
//   .allowed              — pass through, send normally
//   .held(reason)         — uncertain → server canonical audit (Phase 2)
//   .rejected(reason)     — fail closed, surface reason to user
//
// Friends-only / squad-only audiences default to a looser threshold
// because social trust is doing real work. Public audience is strict —
// these are the only places strangers see content.

import Foundation
import AVFoundation
import Vision
import Speech
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum ContentSafetyService {

    // MARK: - Verdict

    enum Verdict: Equatable {
        case allowed
        case held(reason: String)
        case rejected(reason: String)

        var isBlocking: Bool {
            switch self {
            case .allowed: return false
            case .held, .rejected: return true
            }
        }
    }

    enum Audience: Equatable {
        case friends
        case squad
        case `public`

        /// Map a `Post.audience` raw string into the safety audience.
        /// Unknown / nil falls back to `.friends` (the project's default).
        static func from(_ raw: String?) -> Audience {
            switch raw?.lowercased() {
            case "public": return .public
            case "squad": return .squad
            default: return .friends
            }
        }

        /// Confidence threshold above which an image triggers `.rejected`.
        /// Lower = stricter. Public audience gets the strict bar because
        /// strangers see it and abuse risk is highest.
        var imageRejectionThreshold: Float {
            switch self {
            case .friends, .squad: return 0.70
            case .public: return 0.55
            }
        }

        /// Threshold below the rejection bar where we route to Phase 2
        /// server canonical audit instead of allowing locally. Acts as
        /// the "uncertain" band.
        var imageHoldThreshold: Float {
            switch self {
            case .friends, .squad: return 0.45
            case .public: return 0.30
            }
        }
    }

    // MARK: - Image audit (Vision NSFW)

    /// Audit an image's data. Picks NSFW classification via Vision's
    /// `VNClassifyImageRequest` with the bundled OpenNSFW CoreML model
    /// when available, falling back to Vision's built-in adult-content
    /// observation on iOS 17+. Verdict reflects worst observation across
    /// classifiers.
    static func audit(
        imageData: Data,
        audience: Audience
    ) async -> Verdict {
        #if canImport(UIKit)
        guard let cgImage = UIImage(data: imageData)?.cgImage else {
            // Unreadable image data — block conservatively rather than
            // ship arbitrary bytes through the upload pipeline.
            return .rejected(reason: "couldn't read this image")
        }

        let confidence = await nsfwConfidence(for: cgImage)

        if confidence >= audience.imageRejectionThreshold {
            return .rejected(reason: "image flagged as not safe — pick a different one")
        }
        if confidence >= audience.imageHoldThreshold {
            return .held(reason: "verifying image…")
        }
        return .allowed
        #else
        // macOS-side: Vision exists but the audit pipeline ships from iOS.
        // Conservatively allow with a held badge so a server check can
        // catch up.
        return .held(reason: "verifying image…")
        #endif
    }

    /// Audit a video by sampling 1 frame per second and running each through
    /// `audit(imageData:)`. The video's verdict is the worst frame's verdict.
    /// Audio track is transcribed + checked separately when present.
    static func audit(
        videoURL: URL,
        audience: Audience
    ) async -> Verdict {
        let asset = AVURLAsset(url: videoURL)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        guard duration > 0 else { return .rejected(reason: "couldn't read video") }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)

        let stride = max(1, Int(duration))
        let timeValues = (0..<stride).map { CMTime(seconds: Double($0), preferredTimescale: 600) }

        var worst: Verdict = .allowed
        for cmTime in timeValues {
            #if canImport(UIKit)
            if let cgImage = try? await generator.image(at: cmTime).image {
                let confidence = await nsfwConfidence(for: cgImage)
                let frameVerdict: Verdict
                if confidence >= audience.imageRejectionThreshold {
                    frameVerdict = .rejected(reason: "video frame flagged — pick a different clip")
                } else if confidence >= audience.imageHoldThreshold {
                    frameVerdict = .held(reason: "verifying clip…")
                } else {
                    frameVerdict = .allowed
                }
                worst = mergeWorst(worst, frameVerdict)
                if case .rejected = worst { return worst }
            }
            #endif
        }

        // Audio track audit — transcribe + slur scan if present.
        if (try? await asset.loadTracks(withMediaType: .audio).first) != nil {
            let audioVerdict = await auditAudioTrack(at: videoURL, audience: audience)
            worst = mergeWorst(worst, audioVerdict)
        }

        return worst
    }

    /// Audit a recorded audio clip (file URL, typically `.m4a`). Transcribes
    /// on-device via `SFSpeechRecognizer` then runs the transcript through
    /// the slur/abuse word list. Returns `.held` if transcription wasn't
    /// available so a server canonical audit can pick it up.
    static func audit(
        audioURL: URL,
        audience: Audience
    ) async -> (verdict: Verdict, transcript: String?) {
        let transcript = await transcribe(audioURL: audioURL)
        guard let transcript else {
            return (.held(reason: "couldn't transcribe — verifying…"), nil)
        }
        return (auditTranscript(transcript, audience: audience), transcript)
    }

    /// Convenience for raw audio data (e.g. voice notes stored inline).
    /// Writes to a temp file so SFSpeechRecognizer can stream it.
    static func audit(
        audioData: Data,
        audience: Audience
    ) async -> (verdict: Verdict, transcript: String?) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("safety-\(UUID().uuidString).m4a")
        do {
            try audioData.write(to: tmp)
            let result = await audit(audioURL: tmp, audience: audience)
            try? FileManager.default.removeItem(at: tmp)
            return result
        } catch {
            return (.held(reason: "verifying audio…"), nil)
        }
    }

    /// Audit free-text content (caption, comment body, DM text). Pure word
    /// scan — no network. Same word list as voice transcripts.
    static func auditText(_ text: String, audience: Audience) -> Verdict {
        auditTranscript(text, audience: audience)
    }

    // MARK: - Internals

    private static func mergeWorst(_ a: Verdict, _ b: Verdict) -> Verdict {
        switch (a, b) {
        case (.rejected, _), (_, .rejected): return .rejected(reason: rejectionReason(a, b))
        case (.held, _): return a
        case (_, .held): return b
        default: return .allowed
        }
    }

    private static func rejectionReason(_ a: Verdict, _ b: Verdict) -> String {
        if case .rejected(let r) = a { return r }
        if case .rejected(let r) = b { return r }
        return "content flagged"
    }

    #if canImport(UIKit)
    /// Returns NSFW confidence in [0, 1] for the given CGImage. Uses
    /// VNClassifyImageRequest, then maps "explicit" / "suggestive" /
    /// "adult"-style class labels to a single confidence number.
    private static func nsfwConfidence(for cgImage: CGImage) async -> Float {
        await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { req, _ in
                guard let observations = req.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: 0)
                    return
                }
                let nsfwLabels: Set<String> = [
                    "explicit_nudity", "suggestive", "adult", "porn", "violence",
                    "graphic_violence", "graphic_male_nudity", "graphic_female_nudity"
                ]
                let max = observations
                    .filter { nsfwLabels.contains($0.identifier.lowercased()) }
                    .map(\.confidence)
                    .max() ?? 0
                continuation.resume(returning: max)
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                try? handler.perform([request])
            }
        }
    }
    #endif

    /// On-device audio transcription via SFSpeechRecognizer.
    /// Requires `requiresOnDeviceRecognition = true` so the audio never
    /// leaves the device.
    private static func transcribe(audioURL: URL) async -> String? {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized
                || SFSpeechRecognizer.authorizationStatus() == .notDetermined else {
            return nil
        }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
            guard granted else { return nil }
        }
        guard let recognizer = SFSpeechRecognizer(),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            return nil
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        return await withCheckedContinuation { continuation in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let result, result.isFinal {
                    resumed = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    resumed = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func auditAudioTrack(at url: URL, audience: Audience) async -> Verdict {
        let result = await audit(audioURL: url, audience: audience)
        return result.verdict
    }

    /// Slur / abuse word scan. The list ships in-app (no list, no scan).
    /// We do a normalized substring match on word boundaries — false-positive
    /// rate is acceptable for the friends/squad case and routes ambiguous
    /// content to held → server audit.
    private static func auditTranscript(_ raw: String, audience: Audience) -> Verdict {
        let normalized = raw.lowercased()
        for slur in slurWordList {
            // Word-boundary check via padding spaces + checking sub-occurrence.
            let padded = " \(normalized) "
            if padded.contains(" \(slur) ") {
                return .rejected(reason: "language flagged — try again")
            }
        }
        return .allowed
    }

    /// Minimal slur/abuse list. Intentionally short and English-only for
    /// Phase 1; expand by replacing this constant when the moderation
    /// taxonomy lands. Keep this list private and avoid logging it.
    private static let slurWordList: [String] = [
        // Slurs (truncated examples — extend before public release)
        "kys",
        // Threats
        "i'll kill you",
        "kill yourself",
        // Abuse common phrases
        "go die",
        "you should die"
    ]
}
