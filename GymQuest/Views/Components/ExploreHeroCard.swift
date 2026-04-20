import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Tonight's Pick hero card — now a swipeable carousel over N ranked
/// suggestions. The top accent bar acts as a progress fill (8s per
/// pick); when it reaches 100% the card auto-advances. Tap the shuffle
/// button to advance manually, swipe left/right to navigate. The dot row
/// below shows position in the rotation.
struct ExploreHeroCard: View {
    let post: Post
    let rationale: String
    let isSaved: Bool
    /// Total picks in the rotation (for the position dots). Pass the size
    /// of the hero carousel from the caller.
    let picksCount: Int
    /// 0-based index of the currently displayed pick.
    let currentIndex: Int
    let onStart: () -> Void
    let onPreview: () -> Void
    let onToggleSave: () -> Void
    /// Advance to the next pick (right swipe / shuffle button / auto).
    var onAdvance: (() -> Void)? = nil
    /// Step back to the previous pick (left swipe).
    var onRewind: (() -> Void)? = nil
    var onLongPressSave: (() -> Void)? = nil

    /// Seconds the progress bar takes to fill before auto-advancing.
    private let fillDuration: Double = 8

    private var ttl: String {
        if let d = post.sharedWorkoutData, let s = try? JSONDecoder().decode(SharedWorkoutData.self, from: d), !s.title.isEmpty { return s.title }
        return post.exerciseHighlight ?? post.workoutType?.capitalized ?? "Workout"
    }
    private var dur: String { post.duration.map { "\($0) min" } ?? "—" }
    private var tp: String { post.workoutType?.capitalized ?? "Workout" }
    private var auth: String { "@\(post.authorUsername)" }
    private var ini: String { String(post.authorName.prefix(1)).uppercased() }
    private var did: Int { max(post.timesUsed, post.likeCount / 2 + 1) }

    var body: some View {
        VStack(spacing: 0) {
            // .id(currentIndex) forces a fresh subview per pick — the
            // progress state resets cleanly and the new fill animation
            // starts from 0 every time. Auto-advance is disabled when
            // there's only one pick.
            HeroProgressBar(
                duration: fillDuration,
                active: picksCount > 1,
                onComplete: { onAdvance?() }
            )
            .id(currentIndex)

            cardBody
        }
        .background(GQColors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(GQColors.borderDefault, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .gqShadow(.elevated)
        .gesture(
            // Horizontal swipe: left → advance, right → rewind. Threshold
            // avoids accidental triggers from vertical scroll motion.
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let horizontal = value.translation.width
                    guard abs(horizontal) > abs(value.translation.height) else { return }
                    if horizontal < -40 {
                        onAdvance?()
                    } else if horizontal > 40 {
                        onRewind?()
                    }
                }
        )
    }

    private var cardBody: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                    ZStack {
                        thumbnail
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        ZStack {
                            Circle().fill(.black.opacity(0.35)).frame(width: 28, height: 28)
                            Image(systemName: "play.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onPreview)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("TONIGHT'S PICK")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(1.2)
                                .foregroundColor(GQColors.textTertiary)
                            Spacer()
                            if onAdvance != nil {
                                Button(action: {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    onAdvance?()
                                }) {
                                    Image(systemName: "shuffle")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(GQColors.textTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text(ttl)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(GQColors.textPrimary)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Circle().fill(GQGradients.primary).frame(width: 20, height: 20)
                                .overlay(Text(ini).font(.system(size: 8, weight: .bold)).foregroundColor(.white))
                            Text(auth).font(.system(size: 10)).foregroundColor(GQColors.textTertiary)
                            Text("·")
                            Text(tp).font(.system(size: 9, weight: .bold))
                                .foregroundStyle(GQGradients.primary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(GQGradients.primary.opacity(0.08))
                                .clipShape(Capsule())
                            Text(dur).font(.system(size: 11)).foregroundColor(GQColors.textTertiary)
                        }
                        .font(.system(size: 10))
                        .foregroundColor(GQColors.textTertiary)

                        HStack(spacing: 4) {
                            HStack(spacing: -4) {
                                ForEach(0..<min(did, 3), id: \.self) { i in
                                    Circle()
                                        .fill(GQGradients.primary.opacity(0.12 + Double(3 - i) * 0.2))
                                        .frame(width: 16, height: 16)
                                        .overlay(Circle().stroke(GQColors.background, lineWidth: 1))
                                }
                            }
                            Text("+\(did) did this")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(GQColors.textTertiary)
                            Spacer()
                            Button(action: {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                #endif
                                onStart()
                            }) {
                                Text("Start ▸")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(GQGradients.primary)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Capsule().fill(GQGradients.primary.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // N-dot position indicator — one dot per pick, current is
                // the elongated capsule.
                if picksCount > 1 {
                    HStack(spacing: 3) {
                        ForEach(0..<picksCount, id: \.self) { i in
                            Capsule()
                                .fill(i == currentIndex
                                      ? AnyShapeStyle(GQGradients.primary)
                                      : AnyShapeStyle(GQColors.adaptiveOverlay(0.12)))
                                .frame(width: i == currentIndex ? 14 : 4, height: 4)
                                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: currentIndex)
                        }
                    }
                }
            }
            .padding(12)
    }


    @ViewBuilder
    private var thumbnail: some View {
        #if canImport(UIKit)
        if let data = primaryThumbData(), let img = UIImage(data: data) {
            Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(GQGradients.primary.opacity(0.08))
                Image(systemName: "dumbbell.fill").font(.system(size: 24, weight: .light)).foregroundStyle(GQGradients.primary)
            }
        }
        #else
        RoundedRectangle(cornerRadius: 12).fill(GQColors.surfaceSecondary)
        #endif
    }

    private func primaryThumbData() -> Data? {
        if let first = post.mediaItems.first { return first.thumbnailData ?? first.data }
        return post.photoData
    }
}

/// Top 4pt accent that fills 0 → 100% over `duration`, then fires
/// `onComplete`. Parent `.id()`s this view per pick so it mounts fresh
/// with progress = 0 each time — no reset logic needed, no race between
/// old-cycle teardown and new-cycle start.
private struct HeroProgressBar: View {
    let duration: Double
    let active: Bool
    let onComplete: () -> Void

    @State private var progress: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(GQGradients.primary.opacity(0.12))
                Rectangle()
                    .fill(GQGradients.primary)
                    .frame(width: geo.size.width * CGFloat(progress))
                    .animation(.linear(duration: duration), value: progress)
            }
        }
        .frame(height: 4)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .task {
            guard active else { return }
            progress = 1
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled { onComplete() }
        }
    }
}
