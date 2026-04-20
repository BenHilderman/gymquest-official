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

    private let spacing: CGFloat = 2

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

    // MARK: - Grid layout with featured cells

    @ViewBuilder
    private func gridLayout(cellSize: CGFloat) -> some View {
        // Build rows: every 9 items, row pattern is [3, 2+featured, 3, featured+2]
        // Simplified: first 3 are small, 4th is featured (2×2), next 2 small beside it,
        // then repeat.
        let grouped = stride(from: 0, to: items.count, by: 9).map { start in
            Array(items[start..<min(start + 9, items.count)])
        }

        LazyVStack(spacing: spacing) {
            ForEach(Array(grouped.enumerated()), id: \.offset) { groupIdx, group in
                gridGroup(group, cellSize: cellSize, groupOffset: groupIdx)
            }
        }
    }

    @ViewBuilder
    private func gridGroup(_ group: [DiscoverFeedItem], cellSize: CGFloat, groupOffset: Int) -> some View {
        // Row 1: always 3 cells. Pads with empty boxes when the last group
        // has 1 or 2 items — otherwise those items used to silently drop.
        if !group.isEmpty {
            HStack(spacing: spacing) {
                ForEach(0..<min(3, group.count), id: \.self) { i in
                    smallCell(group[i], size: cellSize)
                }
                ForEach(0..<max(0, 3 - group.count), id: \.self) { _ in
                    emptyCell(size: cellSize)
                }
            }
        }

        // Row 2-3: featured (2×2) + 2 small stacked (alternating left/right).
        // Smalls column is always rendered with exactly 2 slots — real items
        // fall back to empty tiles so the featured cell has a clean neighbor.
        if group.count >= 4 {
            let featuredOnLeft = groupOffset % 2 == 0
            let featured = group[3]
            let featuredSize = cellSize * 2 + spacing
            let smalls = Array(group.dropFirst(4).prefix(2))

            HStack(spacing: spacing) {
                if featuredOnLeft {
                    featuredCell(featured, size: featuredSize)
                    smallColumn(smalls, cellSize: cellSize)
                } else {
                    smallColumn(smalls, cellSize: cellSize)
                    featuredCell(featured, size: featuredSize)
                }
            }
        }

        // Row 4: trailing small cells. Always padded to 3.
        let remaining = Array(group.dropFirst(6))
        if !remaining.isEmpty {
            HStack(spacing: spacing) {
                ForEach(remaining) { item in
                    smallCell(item, size: cellSize)
                }
                ForEach(0..<max(0, 3 - remaining.count), id: \.self) { _ in
                    emptyCell(size: cellSize)
                }
            }
        }
    }

    /// Two-slot column next to a 2×2 featured cell. Pads with empty tiles
    /// so the featured is never beside a single floating small tile.
    private func smallColumn(_ smalls: [DiscoverFeedItem], cellSize: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(0..<min(2, smalls.count), id: \.self) { i in
                smallCell(smalls[i], size: cellSize)
            }
            ForEach(0..<max(0, 2 - smalls.count), id: \.self) { _ in
                emptyCell(size: cellSize)
            }
        }
        .frame(width: cellSize)
    }

    /// Visible empty tile that occupies a grid slot. Matches the cell
    /// corner radius and surface color so the pad reads as a natural
    /// "end of feed" gap rather than a layout glitch.
    private func emptyCell(size: CGFloat) -> some View {
        Rectangle()
            .fill(GQColors.adaptiveOverlay(0.03))
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Small cell (1×1 square thumbnail)

    private func smallCell(_ item: DiscoverFeedItem, size: CGFloat) -> some View {
        Button {
            handleTap(item)
        } label: {
            ZStack {
                thumbnailView(item.post)
                    .frame(width: size, height: size)
                    .clipped()

                // Top-right: play icon for video OR multi-image badge
                if isVideo(item) {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8, weight: .bold))
                        if item.post.mediaItems.count > 1 {
                            Text("\(item.post.mediaItems.count)")
                                .font(.system(size: 8, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
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

                // Bottom-right: engagement
                if item.post.likeCount > 5 {
                    HStack(spacing: 2) {
                        Image(systemName: "heart.fill").font(.system(size: 7))
                        Text("\(item.post.likeCount)")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.45)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 4))
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
