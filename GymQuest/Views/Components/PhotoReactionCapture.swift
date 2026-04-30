// Photo reaction capture — design v4.3 §9.
// Tap-to-capture 2-second video loop. Server-side expiry: 7 days.

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class PhotoReactionCaptureModel: ObservableObject {
    @Published var isCapturing: Bool = false
    @Published var lastClipURL: URL?
    static let clipDuration: TimeInterval = 2.0

    /// Stub-record using a 2-sec elapsed timer. Real capture wires
    /// `AVCaptureMovieFileOutput` against the front camera elsewhere; this
    /// component owns the timing + completion contract.
    func capture(onComplete: @escaping (URL) -> Void) {
        guard !isCapturing else { return }
        isCapturing = true
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-react-\(UUID().uuidString).mov")
        lastClipURL = url
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.clipDuration) { [weak self] in
            self?.isCapturing = false
            onComplete(url)
        }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

struct PhotoReactionCaptureButton: View {
    @StateObject private var model = PhotoReactionCaptureModel()
    var onCaptured: (URL) -> Void

    var body: some View {
        Button { model.capture(onComplete: onCaptured) } label: {
            ZStack {
                Circle()
                    .fill(model.isCapturing ? Color.red : Color.white.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "camera.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                if model.isCapturing {
                    Circle()
                        .stroke(Color.red, lineWidth: 2)
                        .frame(width: 50, height: 50)
                        .scaleEffect(1.0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture photo reaction (2 seconds)")
    }
}

struct PhotoReactionLoopThumb: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        VideoLoopView(player: $player)
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onAppear {
                let item = AVPlayerItem(url: url)
                let queue = AVQueuePlayer(playerItem: item)
                looper = AVPlayerLooper(player: queue, templateItem: item)
                player = queue
                queue.isMuted = true
                queue.play()
            }
            .onDisappear { player?.pause(); player = nil; looper = nil }
    }
}

#if canImport(UIKit)
private struct VideoLoopView: UIViewRepresentable {
    @Binding var player: AVPlayer?
    func makeUIView(context: Context) -> PlayerContainerView { PlayerContainerView() }
    func updateUIView(_ view: PlayerContainerView, context: Context) {
        view.playerLayer.player = player
    }
}

final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    override init(frame: CGRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspectFill
    }
    required init?(coder: NSCoder) { fatalError() }
}
#else
private struct VideoLoopView: View {
    @Binding var player: AVPlayer?
    var body: some View { Color.black }
}
#endif
