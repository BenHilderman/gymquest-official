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
    /// Tap anywhere on the card (not a nested button) opens the full
    /// post inside a scrolling recommendation feed.
    let onOpen: () -> Void
    let onToggleSave: () -> Void
    /// Advance to the next pick (right swipe / shuffle button / auto).
    var onAdvance: (() -> Void)? = nil
    /// Step back to the previous pick (left swipe).
    var onRewind: (() -> Void)? = nil
    /// Jump directly to a specific pick (dot tap).
    var onJumpTo: ((Int) -> Void)? = nil
    var onLongPressSave: (() -> Void)? = nil

    /// Seconds the progress bar takes to fill before auto-advancing.
    private let fillDuration: Double = 10

    private var ttl: String {
        if let d = post.sharedWorkoutData, let s = try? JSONDecoder().decode(SharedWorkoutData.self, from: d), !s.title.isEmpty { return s.title }
        return post.exerciseHighlight ?? post.workoutType?.capitalized ?? "Workout"
    }
    private var dur: String { post.duration.map { "\($0) min" } ?? "—" }
    private var tp: String { post.workoutType?.capitalized ?? "Workout" }
    private var auth: String { "@\(post.authorUsername)" }
    private var ini: String { String(post.authorName.prefix(1)).uppercased() }

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

            // Tap on the card body (outside the shuffle / Start /
            // thumbnail / dot buttons) opens the full post in the
            // recommended-posts feed. The Start button itself fires
            // onStart — so the only way into the workout overview is
            // through the explicit Start action.
            cardBody
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
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
                    .onTapGesture(perform: onOpen)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("FOR YOU")
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

                        // Icon-only actions matching the post card's
                        // action row: bookmark to save, play.circle to
                        // start. Same language so behavior is predictable
                        // whether the user is on a hero card or a post.
                        HStack(spacing: 14) {
                            Spacer()
                            Button {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                onToggleSave()
                            } label: {
                                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 18))
                                    .foregroundStyle(isSaved ? AnyShapeStyle(GQGradients.primary) : AnyShapeStyle(GQColors.textTertiary))
                            }
                            .buttonStyle(.plain)

                            Button {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                #endif
                                onStart()
                            } label: {
                                Image(systemName: "play.circle")
                                    .font(.system(size: 20))
                                    .foregroundStyle(GQGradients.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Tappable position indicator — each pick is a button so
                // users can jump directly to any of the 5 picks. Hit
                // target tightened (14pt tall vs 24) to remove the
                // extra vertical air that made the card bottom feel long.
                if picksCount > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<picksCount, id: \.self) { i in
                            Button {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                                onJumpTo?(i)
                            } label: {
                                Capsule()
                                    .fill(i == currentIndex
                                          ? AnyShapeStyle(GQGradients.primary)
                                          : AnyShapeStyle(GQColors.adaptiveOverlay(0.18)))
                                    .frame(width: i == currentIndex ? 22 : 8, height: 6)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: currentIndex)
                                    .frame(height: 14)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
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
