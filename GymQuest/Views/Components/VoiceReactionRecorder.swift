// Voice & photo reaction capture/playback — design v4.3 §9.
// Hold-to-record voice (max 5 sec), tap-to-capture photo (2-sec loop).
// Server-side photo expiry is enforced via reactions.photo_expires_at.

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class VoiceReactionRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording: Bool = false
    @Published var elapsed: TimeInterval = 0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var lastFileURL: URL?

    static let maxDuration: TimeInterval = 5.0

    func start() {
        guard !isRecording else { return }
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            return
        }
        #endif
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.record(forDuration: Self.maxDuration)
            self.recorder = recorder
            self.lastFileURL = url
            isRecording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.elapsed += 0.1
                    if self.elapsed >= Self.maxDuration { self.stop() }
                }
            }
        } catch {
            isRecording = false
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isRecording = false
            self?.timer?.invalidate()
            self?.timer = nil
        }
    }
}

@MainActor
final class VoiceReactionPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var isPlaying: Bool = false
    private var player: AVAudioPlayer?

    func play(url: URL) {
        guard !isPlaying else { return }
        do {
            #if canImport(UIKit)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            #endif
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
            isPlaying = true
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        } catch {
            isPlaying = false
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in self?.isPlaying = false }
    }
}

/// Hold-to-record button for voice reactions. Plays a haptic on press,
/// stops automatically at the 5-sec cap, and exposes the resulting file URL.
struct VoiceReactionRecordButton: View {
    @StateObject private var recorder = VoiceReactionRecorder()
    var onComplete: (URL) -> Void

    var body: some View {
        Image(systemName: recorder.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
            .font(.system(size: 44))
            .foregroundStyle(recorder.isRecording ? Color.red : Color.accentColor)
            .scaleEffect(recorder.isRecording ? 1.1 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: recorder.isRecording)
            .gesture(
                LongPressGesture(minimumDuration: 0.05)
                    .onEnded { _ in
                        recorder.start()
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                    }
                    .simultaneously(with: DragGesture(minimumDistance: 0)
                        .onEnded { _ in
                            recorder.stop()
                            if let url = recorder.lastFileURL { onComplete(url) }
                        }
                    )
            )
            .accessibilityLabel("Hold to record voice reaction")
    }
}

/// 30-second voice-note recorder for comment replies. Same shape as
/// `VoiceReactionRecorder` but with a longer cap because comments are
/// the deeper-engagement surface (vs the 5-sec quick reaction).
@MainActor
final class CommentVoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording: Bool = false
    @Published var elapsed: TimeInterval = 0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var lastFileURL: URL?

    static let maxDuration: TimeInterval = 30.0

    func start() {
        guard !isRecording else { return }
        #if canImport(UIKit)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            return
        }
        #endif
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("comment-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.delegate = self
            recorder.record(forDuration: Self.maxDuration)
            self.recorder = recorder
            self.lastFileURL = url
            isRecording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.elapsed += 0.1
                    if self.elapsed >= Self.maxDuration { self.stop() }
                }
            }
        } catch {
            isRecording = false
        }
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isRecording = false
            self?.timer?.invalidate()
            self?.timer = nil
        }
    }
}

/// Inline player for an existing voice reaction.
struct VoiceReactionPlayButton: View {
    @StateObject private var player = VoiceReactionPlayer()
    let url: URL
    var compact: Bool = false

    var body: some View {
        Button {
            player.play(url: url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                if !compact {
                    Image(systemName: "waveform")
                        .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.18)))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
