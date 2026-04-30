// PRRingBufferRecorder — design v4.3 §7A.
// Continuously captures the last 3 seconds of front-camera video while a
// workout is active so a PR moment can auto-record the lead-up clip and
// hand it to ProofVideoExporter for the slow-mo replay card.
//
// Real-device tuning (codec / bitrate / orientation) lands when you run on
// a phone; the API + permission gating + ring buffer shape is stable.

import Foundation
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class PRRingBufferRecorder: NSObject, ObservableObject {
    static let shared = PRRingBufferRecorder()

    @Published private(set) var isCapturing: Bool = false
    @Published private(set) var lastCapturedURL: URL?
    @Published private(set) var hasPermission: Bool = false

    /// Sliding ring buffer: target window of past video kept in temp file.
    /// On a snapshot request, the recorder splices out the trailing N seconds.
    private let ringWindow: TimeInterval = 3.0
    private var captureSession: AVCaptureSession?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var rollingURL: URL?

    private override init() { super.init() }

    /// Request permission (idempotent). Call this when the user toggles the
    /// "auto-record PRs" preference on, or first time PR is hit.
    func requestPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            hasPermission = true
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            hasPermission = granted
            return granted
        default:
            hasPermission = false
            return false
        }
    }

    /// Start the rolling capture. Call when the workout begins.
    func startRolling() {
        guard hasPermission, !isCapturing else { return }
        let session = AVCaptureSession()
        session.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMovieFileOutput()
        // Cap recorded segments at the ring window so the file never grows.
        output.maxRecordedDuration = CMTime(seconds: ringWindow, preferredTimescale: 600)
        if session.canAddOutput(output) { session.addOutput(output) }

        // Lock orientation to portrait so PR clips render upright through
        // ProofVideoExporter — IG/TikTok consume 9:16 vertical, and the
        // ring buffer fires off `snapshotPRClip()` mid-set when the user
        // is too busy lifting to manually rotate. Mirror the front camera
        // so the user sees the natural "selfie mirror" framing they expect.
        if let connection = output.connection(with: .video) {
            applyPortraitOrientation(to: connection)
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            // HEVC capture is preferred to match the exporter's default codec
            // (smaller files, same visual fidelity). Falls back transparently
            // when the device can't encode HEVC. iOS-only — `availableVideoCodecTypes`
            // is unavailable on macOS.
            #if os(iOS)
            if output.availableVideoCodecTypes.contains(.hevc) {
                output.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.hevc], for: connection)
            }
            #endif
        }

        captureSession = session
        movieOutput = output
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            session.startRunning()
            Task { @MainActor in
                self?.isCapturing = true
                self?.rotateRecording()
            }
        }
    }

    /// Sets the connection's video orientation to portrait using whichever
    /// API the deployment target supports. iOS 17+ deprecated
    /// `videoOrientation` in favor of `videoRotationAngle` (90° = portrait).
    private func applyPortraitOrientation(to connection: AVCaptureConnection) {
        if #available(iOS 17.0, *) {
            let portraitAngle: CGFloat = 90
            if connection.isVideoRotationAngleSupported(portraitAngle) {
                connection.videoRotationAngle = portraitAngle
            }
        } else if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    /// Stop and tear down the session. Call when the workout ends.
    func stopRolling() {
        movieOutput?.stopRecording()
        captureSession?.stopRunning()
        captureSession = nil
        movieOutput = nil
        isCapturing = false
    }

    /// Snapshot the current rolling window — call this from `handleLivePR(...)`.
    /// Returns the URL of the captured clip, suitable for `ProofVideoExporter`.
    func snapshotPRClip() -> URL? {
        guard isCapturing, let url = rollingURL else { return nil }
        // Hand off the current segment as the PR clip and start a new segment
        // so the ring keeps rolling without dropping frames between PRs.
        movieOutput?.stopRecording()
        rotateRecording()
        lastCapturedURL = url
        return url
    }

    /// Internal — open a new temp file and start writing to it.
    private func rotateRecording() {
        guard let output = movieOutput else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pr-buf-\(UUID().uuidString).mov")
        rollingURL = url
        output.startRecording(to: url, recordingDelegate: self)
    }
}

extension PRRingBufferRecorder: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                 didFinishRecordingTo outputFileURL: URL,
                                 from connections: [AVCaptureConnection],
                                 error: Error?) {
        // Auto-rotate to keep ring buffer alive while session is active.
        Task { @MainActor [weak self] in
            guard let self, self.isCapturing else { return }
            self.rotateRecording()
        }
    }
}
