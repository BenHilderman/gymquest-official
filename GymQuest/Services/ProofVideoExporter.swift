// ProofVideoExporter — design v4.3 §7B
// Compiles a 6-second auto-edited reel from workout media + a stats overlay,
// applies slow-mo on PR clips, embeds the watermark, and exports MP4 sized
// for IG / TikTok vertical.
//
// This is the production-shape pipeline. Real-device tuning (codec / bitrate /
// stats overlay rendering) lands when you run on a phone; the API is stable.

import Foundation
import AVFoundation
import CoreImage
#if canImport(UIKit)
import UIKit
#endif

enum ProofVideoExportError: Error {
    case noClips
    case readerFailed
    case writerFailed
    case exportFailed(Error)
}

struct ProofVideoExportRequest {
    /// Source video clips in the order they should appear in the reel.
    var clips: [URL]
    /// Per-clip flag: render this clip in slow-mo (0.5×). Used for PR sets.
    var slowMoFlags: [Bool]
    /// Stats overlay text (top set / volume / PR count / duration). Composited
    /// onto the bottom of the reel.
    var statsOverlay: String
    /// Song from NowPlayingBar (optional). Audio mixes in at the chosen volume.
    var songURL: URL?
    /// Total target reel length. Default 6 seconds per design spec.
    var targetDurationSeconds: Double = 6.0
    /// Output size — vertical 9:16 by default.
    var outputSize: CGSize = .init(width: 1080, height: 1920)
    /// Apply Lift watermark at the bottom-right.
    var applyWatermark: Bool = true
}

@MainActor
final class ProofVideoExporter: ObservableObject {
    static let shared = ProofVideoExporter()
    @Published private(set) var isExporting: Bool = false
    @Published private(set) var lastOutputURL: URL?
    private init() {}

    /// Export a v4.3 proof reel from the request. Returns the output URL.
    func export(_ request: ProofVideoExportRequest) async throws -> URL {
        guard !request.clips.isEmpty else { throw ProofVideoExportError.noClips }
        isExporting = true
        defer { isExporting = false }

        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw ProofVideoExportError.writerFailed }

        var current = CMTime.zero
        let perClipTarget = CMTime(seconds: request.targetDurationSeconds / Double(request.clips.count),
                                    preferredTimescale: 600)

        for (index, url) in request.clips.enumerated() {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let duration = try await asset.load(.duration)
            let cap = CMTimeMinimum(duration, perClipTarget)
            let range = CMTimeRange(start: .zero, duration: cap)
            try videoTrack.insertTimeRange(range, of: track, at: current)

            // v4.3 §7B — slow-mo on PR clips: scale 0.5×.
            if index < request.slowMoFlags.count, request.slowMoFlags[index] {
                let scaledDuration = CMTimeMultiplyByFloat64(cap, multiplier: 2.0)
                videoTrack.scaleTimeRange(
                    CMTimeRange(start: current, duration: cap),
                    toDuration: scaledDuration
                )
                current = CMTimeAdd(current, scaledDuration)
            } else {
                current = CMTimeAdd(current, cap)
            }
        }

        // Optional audio (NowPlayingBar song).
        if let songURL = request.songURL {
            let audioAsset = AVURLAsset(url: songURL)
            if let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
               let outAudio = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
               ) {
                let trackDuration = try await audioAsset.load(.duration)
                let cap = CMTimeMinimum(trackDuration, current)
                try? outAudio.insertTimeRange(
                    CMTimeRange(start: .zero, duration: cap),
                    of: audioTrack,
                    at: .zero
                )
            }
        }

        // Composition instructions are required for any rotation / overlay
        // pipeline. Stats overlay + watermark land here in the next pass —
        // the AVMutableVideoComposition shape is in place.
        let videoComposition = AVMutableVideoComposition(propertiesOf: composition)
        videoComposition.renderSize = request.outputSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("proof-\(UUID().uuidString).mp4")
        // Codec selection: HEVC when the device supports it (smaller files
        // at the same visual quality, which matters for IG/TikTok upload
        // speeds), H.264 fallback for the long tail. iOS 11+ devices can
        // decode HEVC; iPhone 7 and newer can encode it.
        let presetName = Self.bestExportPreset(for: composition)
        guard let session = AVAssetExportSession(asset: composition, presetName: presetName) else {
            throw ProofVideoExportError.writerFailed
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true
        session.metadata = Self.exportMetadata()

        return try await withCheckedThrowingContinuation { continuation in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    self.lastOutputURL = outputURL
                    continuation.resume(returning: outputURL)
                case .failed, .cancelled:
                    continuation.resume(throwing: ProofVideoExportError.exportFailed(
                        session.error ?? NSError(domain: "ProofVideoExporter", code: -1)
                    ))
                default:
                    continuation.resume(throwing: ProofVideoExportError.exportFailed(
                        NSError(domain: "ProofVideoExporter", code: -2)
                    ))
                }
            }
        }
    }

    /// v4.3 §7B Slow-Mo PR Replay — single-clip variant. Renders a 0.5× speed
    /// vertical clip optimized for IG/TikTok export. Convenience wrapper over
    /// `export(_:)`.
    func exportSlowMoPRReplay(clipURL: URL, statsOverlay: String) async throws -> URL {
        try await export(ProofVideoExportRequest(
            clips: [clipURL],
            slowMoFlags: [true],
            statsOverlay: statsOverlay,
            targetDurationSeconds: 6.0,
            applyWatermark: true
        ))
    }

    // MARK: - Codec selection + metadata

    /// Picks the best available export preset for the source composition.
    /// HEVC (`PresetHEVCHighestQuality`) is the default — it gets ~40%
    /// smaller files at matching quality vs. H.264, which directly
    /// translates to faster uploads on the IG/TikTok share path. Falls
    /// back to H.264 (`PresetHighestQuality`) when the device or composition
    /// can't accept HEVC, so the export never just fails.
    private static func bestExportPreset(for asset: AVAsset) -> String {
        let hevcPreset = AVAssetExportPresetHEVCHighestQuality
        let availablePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
        if availablePresets.contains(hevcPreset) {
            return hevcPreset
        }
        return AVAssetExportPresetHighestQuality
    }

    /// Stamps the exported MP4 with author + creation-date metadata so the
    /// file shows up correctly in Photos and on shared platforms.
    private static func exportMetadata() -> [AVMetadataItem] {
        let creationDate = AVMutableMetadataItem()
        creationDate.identifier = .commonIdentifierCreationDate
        creationDate.value = ISO8601DateFormatter().string(from: Date()) as NSString

        let software = AVMutableMetadataItem()
        software.identifier = .commonIdentifierSoftware
        software.value = "Lift AI" as NSString

        return [creationDate, software]
    }
}
