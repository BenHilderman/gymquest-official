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

    /// Tighter than the old 2pt inline spacing — gives every tile room
    /// to breathe without fragmenting the feed.
    private let spacing: CGFloat = 6
    /// 4:5 portrait aspect — matches how fitness content is shot (vertical
    /// on phones) and makes each tile readable instead of thumbnail-dense.
    private let aspectRatio: CGFloat = 4.0 / 5.0
    private let columns = 2

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
        let horizontalPadding: CGFloat = 16
        let totalSpacing = spacing * CGFloat(columns - 1)
        let cellWidth = (screenW - horizontalPadding * 2 - totalSpacing) / CGFloat(columns)
        let cellHeight = cellWidth / aspectRatio
        gridLayout(cellWidth: cellWidth, cellHeight: cellHeight)
            .padding(.horizontal, horizontalPadding)
    }

    // MARK: - Grid layout — uniform 2-column grid of portrait tiles

    @ViewBuilder
    private func gridLayout(cellWidth: CGFloat, cellHeight: CGFloat) -> some View {
        // Truncate to a clean multiple of `columns` so every row is full.
        let truncated = Array(items.prefix(items.count - (items.count % columns)))
        let rows = stride(from: 0, to: truncated.count, by: columns).map { start in
            Array(truncated[start..<min(start + columns, truncated.count)])
        }

        LazyVStack(spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(row) { item in
                        smallCell(item, width: cellWidth, height: cellHeight)
                    }
                }
            }
        }
    }

    // MARK: - Small cell (1×1 square thumbnail)

    private func smallCell(_ item: DiscoverFeedItem, width: CGFloat, height: CGFloat) -> some View {
        Button {
            handleTap(item)
        } label: {
            ZStack {
                thumbnailView(item.post)
                    .frame(width: width, height: height)
                    .clipped()

                // Top-right: play icon for video OR multi-image badge.
                // Slightly larger glyphs now that cells are bigger.
                if isVideo(item) {
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        if item.post.mediaItems.count > 1 {
                            Text("\(item.post.mediaItems.count)")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(6)
                }

                // Bottom-left: duration badge
                if let dur = item.post.duration, dur > 0 {
                    Text("\(dur)m")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(6)
                }

                // Bottom-right: engagement
                if item.post.likeCount > 5 {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill").font(.system(size: 9))
                        Text("\(item.post.likeCount)")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.45)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
