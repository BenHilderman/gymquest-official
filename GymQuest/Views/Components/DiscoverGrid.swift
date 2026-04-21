import SwiftUI
import AVKit
#if canImport(UIKit)
import UIKit
#endif

/// Instagram Explore-style grid. 3 columns with occasional 2×2 featured
/// cells for recommended workouts/videos. Dense thumbnails for scanning
/// many options at once. Videos autoplay muted when scrolled into view.
struct DiscoverGrid: View {
    let items: [DiscoverFeedItem]
    let onTapVideo: (Post) -> Void     // opens fullscreen Shorts
    let onTapPhoto: (Post) -> Void     // opens post detail
    let onStartWorkout: (Post) -> Void

    /// ID of the item currently closest to the viewport center — drives
    /// autoplay on the featured video cell.
    @State private var activeVideoId: String?

    /// Breathing room between tiles — 3-col density preserved.
    private let spacing: CGFloat = 6

    var body: some View {
        // No inner ScrollView — the grid flows directly inside the parent
        // page scroll so it reads as one continuous feed. Cell size is
        // derived from the screen width instead of a GeometryReader
        // (which would greedily claim its own layout space and force
        // nested scrolling).
        #if canImport(UIKit)
        let screenW = UIScreen.main.bounds.width
        #else
        let screenW: CGFloat = 390
        #endif
        let cellSize = (screenW - spacing * 2 - 32) / 3
        gridLayout(cellSize: cellSize)
            .padding(.horizontal, 16)
    }

    // MARK: - Grid layout — uniform 3-column grid of equal squares

    @ViewBuilder
    private func gridLayout(cellSize: CGFloat) -> some View {
        // Truncate to a clean multiple of 3 so every row is full. No
        // featured cells, no orphans, no padding. One consistent square
        // size across the whole feed.
        let truncated = Array(items.prefix(items.count - (items.count % 3)))
        let rows = stride(from: 0, to: truncated.count, by: 3).map { start in
            Array(truncated[start..<min(start + 3, truncated.count)])
        }

        LazyVStack(spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(row) { item in
                        smallCell(item, size: cellSize)
                    }
                }
            }
        }
    }

    // MARK: - Small cell (1×1 square thumbnail)

    private func smallCell(_ item: DiscoverFeedItem, size: CGFloat) -> some View {
        Button {
            handleTap(item)
        } label: {
            ZStack {
                // Video posts: autoplay muted video preview. Photo posts:
                // static thumbnail. The play badge in the corner is gone
                // since videos now actually play, which is a clearer
                // signal than a static icon overlay.
                if isVideo(item), let data = effectiveVideoData(item.post) {
                    GridVideoTile(videoData: data)
                        .frame(width: size, height: size)
                        .clipped()
                } else {
                    thumbnailView(item.post)
                        .frame(width: size, height: size)
                        .clipped()
                }

                // Top-right: multi-image badge (count only — no play icon).
                if item.post.mediaItems.count > 1 {
                    Text("\(item.post.mediaItems.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(4)
                }

                // Top-left: workout type icon so the viewer can sort the
                // grid by intent at a glance (push/pull/legs/cardio).
                if let rawType = item.post.workoutType,
                   let type = WorkoutType(rawValue: rawType) {
                    Image(systemName: type.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(4)
                }

                // Bottom-left: duration badge
                if let dur = item.post.duration, dur > 0 {
                    Text("\(dur)m")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Featured cell (2×2 with autoplay video or large photo)

    private func featuredCell(_ item: DiscoverFeedItem, size: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            #if canImport(UIKit)
            if isVideo(item), let videoData = effectiveVideoData(item.post) {
                ScrollClipVideoPlayer(videoData: videoData, isActive: true, postId: item.post.id)
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                thumbnailView(item.post)
                    .frame(width: size, height: size)
                    .clipped()
            }
            #endif

            // Overlay info
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 3) {
                if let type = item.post.workoutType {
                    Text(type.capitalized)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(.white.opacity(0.25)))
                }
                Text(item.post.caption)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
            .padding(8)

            if item.post.sharedWorkoutData != nil {
                Button { onStartWorkout(item.post) } label: {
                    Text("Start")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(GQGradients.primary))
                }
                .buttonStyle(.plain)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { handleTap(item) }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func thumbnailView(_ post: Post) -> some View {
        #if canImport(UIKit)
        if let data = thumbData(post), let img = UIImage(data: data) {
            Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Rectangle().fill(GQColors.surfaceSecondary)
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(GQColors.textTertiary)
            }
        }
        #else
        Rectangle().fill(GQColors.surfaceSecondary)
        #endif
    }

    private func thumbData(_ post: Post) -> Data? {
        if let first = post.mediaItems.first { return first.thumbnailData ?? first.data }
        return post.photoData
    }

    private func isVideo(_ item: DiscoverFeedItem) -> Bool {
        if case .video = item { return true }
        return false
    }

    private func effectiveVideoData(_ post: Post) -> Data? {
        if let v = post.videoData, v.count >= 1024 { return v }
        if let media = post.mediaItems.first(where: { ($0.data?.count ?? 0) >= 1024 && $0.mediaType == .video }),
           let data = media.data { return data }
        return nil
    }

    private func handleTap(_ item: DiscoverFeedItem) {
        switch item {
        case .video(let post): onTapVideo(post)
        case .photo(let post): onTapPhoto(post)
        case .suggestion(let post, _): onTapPhoto(post)
        }
    }
}

/// Minimal muted looping video tile for the Discover grid. No controls,
/// no mute toggle overlay — the tile is its own preview. Tap routes
/// through the parent's Button which pushes into Shorts for sound + UI.
private struct GridVideoTile: View {
    let videoData: Data

    @State private var player: AVPlayer?
    @State private var tempURL: URL?
    @State private var loopObserver: NSObjectProtocol?

    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .disabled(true)
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
        }
        .onAppear { setup() }
        .onDisappear { teardown() }
    }

    private func setup() {
        guard player == nil else {
            player?.play()
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")
        do {
            try videoData.write(to: url)
            tempURL = url
            let item = AVPlayerItem(url: url)
            let p = AVPlayer(playerItem: item)
            p.isMuted = true
            p.actionAtItemEnd = .none
            loopObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { _ in
                p.seek(to: .zero)
                p.play()
            }
            player = p
            p.play()
        } catch {
            // Fallback: leave player nil — black background shown.
        }
    }

    private func teardown() {
        player?.pause()
        if let obs = loopObserver {
            NotificationCenter.default.removeObserver(obs)
            loopObserver = nil
        }
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url)
            tempURL = nil
        }
        player = nil
    }
}
