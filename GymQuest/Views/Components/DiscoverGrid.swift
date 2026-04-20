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
        // Truncate the feed so the last group renders a *complete* layout —
        // no orphan tiles, no pad-with-blank fills. Each 9-item group can
        // terminate cleanly at exactly 3 (just Row 1), 6 (Row 1 + featured
        // row), or 9 (full pattern). Any other remainder gets dropped so
        // the feed ends on a visually even row.
        let n = items.count
        let fullGroups = n / 9
        let remainder = n % 9
        let validRemainder = remainder >= 6 ? 6 : (remainder >= 3 ? 3 : 0)
        let finalCount = fullGroups * 9 + validRemainder
        let truncated = Array(items.prefix(finalCount))
        let grouped = stride(from: 0, to: truncated.count, by: 9).map { start in
            Array(truncated[start..<min(start + 9, truncated.count)])
        }

        LazyVStack(spacing: spacing) {
            ForEach(Array(grouped.enumerated()), id: \.offset) { groupIdx, group in
                gridGroup(group, cellSize: cellSize, groupOffset: groupIdx)
            }
        }
    }

    @ViewBuilder
    private func gridGroup(_ group: [DiscoverFeedItem], cellSize: CGFloat, groupOffset: Int) -> some View {
        // gridLayout guarantees group.count is 3, 6, or 9, so every row
        // below renders as a complete set of tiles — no blanks, no drops.

        // Row 1: 3 small cells
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { i in
                smallCell(group[i], size: cellSize)
            }
        }

        // Row 2-3: featured (2×2) + 2 stacked smalls. Alternates side so
        // the layout has rhythm without a mechanical stripe.
        if group.count >= 6 {
            let featuredOnLeft = groupOffset % 2 == 0
            let featured = group[3]
            let featuredSize = cellSize * 2 + spacing
            let smalls = [group[4], group[5]]

            HStack(spacing: spacing) {
                if featuredOnLeft {
                    featuredCell(featured, size: featuredSize)
                    VStack(spacing: spacing) {
                        ForEach(smalls) { item in
                            smallCell(item, size: cellSize)
                        }
                    }
                    .frame(width: cellSize)
                } else {
                    VStack(spacing: spacing) {
                        ForEach(smalls) { item in
                            smallCell(item, size: cellSize)
                        }
                    }
                    .frame(width: cellSize)
                    featuredCell(featured, size: featuredSize)
                }
            }
        }

        // Row 4: trailing 3 smalls (only present in full 9-item groups).
        if group.count >= 9 {
            HStack(spacing: spacing) {
                ForEach(6..<9, id: \.self) { i in
                    smallCell(group[i], size: cellSize)
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
