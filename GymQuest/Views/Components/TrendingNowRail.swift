import SwiftUI
import AVKit
#if canImport(UIKit)
import UIKit
#endif

/// Phase 1 of the For You rail redesign. A horizontal carousel of 9:16
/// portrait hero cards, one focused at a time with a peek of the next.
/// Replaces the compact `ExploreHeroCard` row so the For You surface
/// reads as a media-first discovery moment instead of a list row.
///
/// Phase 1 scope:
/// - Static rail (cover photo only, no autoplay video)
/// - Peek of next card via paged horizontal scroll
/// - Auto-advance progress bar (preserves the existing 8-10s cadence
///   from `ExploreHeroCard` so the addictive forward-motion isn't
///   regressed during the rebuild)
/// - Page dots, tap-to-open, long-press-to-save
///
/// Later phases layer on autoplay video previews, live signal chips,
/// and the "Today's Mix" sequence player.
struct TrendingNowRail: View {
    let picks: [Post]
    /// Externally-driven index — the parent owns it so auto-advance
    /// from the existing `advanceHero()`/`rewindHero()` helpers in
    /// ExploreView keeps working without rewiring.
    @Binding var currentIndex: Int
    var onTapPost: (Post) -> Void
    var onLongPressSave: ((Post) -> Void)? = nil
    var onShuffle: (() -> Void)? = nil
    var onAdvance: (() -> Void)? = nil

    /// How long the auto-advance progress bar takes to fill. Matches
    /// the previous hero card's cadence.
    private let fillDuration: Double = 10

    @State private var scrollPosition: Int? = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            // Auto-advance bar — keyed on currentIndex so it resets and
            // re-fires `onAdvance` every time we land on a new card.
            HeroProgressBar(
                duration: fillDuration,
                active: picks.count > 1,
                onComplete: { onAdvance?() }
            )
            .id(currentIndex)
            .padding(.horizontal, 16)

            rail

            if picks.count > 1 {
                pageDots
                    .padding(.horizontal, 16)
            }
        }
        .onAppear {
            scrollPosition = currentIndex
        }
        .onChange(of: currentIndex) { _, new in
            // Sync the scroll position when the parent advances the
            // index (auto-advance, shuffle button, dot tap).
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                scrollPosition = new
            }
        }
        .onChange(of: scrollPosition) { _, new in
            // User scrolled manually — bubble the new index up so the
            // parent's heroIndex stays in sync.
            if let new, new != currentIndex {
                currentIndex = new
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(GQGradients.primary)
            Text("FOR YOU")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(GQColors.textTertiary)
            Spacer()
            if onShuffle != nil {
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    onShuffle?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Shuffle")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(GQColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Rail

    @ViewBuilder
    private var rail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(Array(picks.enumerated()), id: \.element.id) { idx, post in
                    TrendingHeroCard(post: post, isFocused: idx == currentIndex)
                        .id(idx)
                        .onTapGesture {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                            onTapPost(post)
                        }
                        .onLongPressGesture(minimumDuration: 0.4) {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            #endif
                            onLongPressSave?(post)
                        }
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 16)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollPosition)
    }

    // MARK: - Page Dots

    @ViewBuilder
    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<picks.count, id: \.self) { i in
                Capsule()
                    .fill(i == currentIndex
                          ? AnyShapeStyle(GQGradients.primary)
                          : AnyShapeStyle(GQColors.adaptiveOverlay(0.18)))
                    .frame(width: i == currentIndex ? 18 : 5, height: 5)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: currentIndex)
            }
            Spacer()
        }
    }
}

// MARK: - Trending Hero Card (single 9:16 pick)

/// Big portrait media card — the visual upgrade over the old compact
/// row. Cover photo fills the frame, gradient at the bottom holds the
/// caption + author chip + workout-type pill.
private struct TrendingHeroCard: View {
    let post: Post
    /// True only for the card currently centered in the rail. Drives
    /// autoplay so we have at most one decoded video alive at a time.
    var isFocused: Bool = false

    /// AVPlayer for the focused card's preview. Created in `.task` when
    /// the card becomes focused and the post has video data; torn down
    /// when focus moves elsewhere (or the card disappears) so memory
    /// returns to the next card immediately.
    @State private var player: AVPlayer?
    /// Notification observer token for the loop callback — held so we
    /// can remove it on teardown to avoid leaking observers.
    @State private var loopObserver: NSObjectProtocol?

    private var hasVideo: Bool { post.videoData != nil }

    private var title: String {
        if let data = post.sharedWorkoutData,
           let shared = try? JSONDecoder().decode(SharedWorkoutData.self, from: data),
           !shared.title.isEmpty {
            return shared.title
        }
        return post.exerciseHighlight ?? post.workoutType?.capitalized ?? post.caption.prefix(40).description
    }

    private var workoutChip: String? {
        post.workoutType?.capitalized
    }

    private var durationText: String? {
        post.duration.map { "\($0) min" }
    }

    private var initials: String {
        String(post.authorName.prefix(1)).uppercased()
    }

    private func coverData() -> Data? {
        if let first = post.mediaItems.first { return first.thumbnailData ?? first.data }
        return post.photoData
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Focused card with video → autoplay; everything else uses
            // the static cover. Cover stays as the visible layer until
            // the player is ready so there's no empty-frame flash on
            // focus change.
            cover

            #if canImport(UIKit)
            if isFocused, hasVideo, let player {
                RawVideoView(player: player)
                    .frame(width: 260, height: 360)
                    .clipped()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            #endif

            // Bottom gradient so caption text is legible regardless of
            // cover photo brightness.
            LinearGradient(
                colors: [.clear, .black.opacity(0.5), .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            // Top-right chip — workout type pill in the brand gradient.
            // Sits above the gradient so it's visible against bright
            // cover photos.
            VStack {
                HStack {
                    Spacer()
                    if let chip = workoutChip {
                        Text(chip)
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.4)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(GQGradients.primary))
                    }
                }
                Spacer()
            }
            .padding(10)

            // Bottom content
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Circle()
                        .fill(GQGradients.primary)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Text(initials)
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.white)
                        )
                    Text("@\(post.authorUsername)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                    if let dur = durationText {
                        Text("·")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.5))
                        Text(dur)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Spacer()
                }
            }
            .padding(12)
        }
        .frame(width: 260, height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(GQColors.borderDefault.opacity(0.6), lineWidth: 0.5)
        )
        .gqShadow(.card)
        .task(id: focusKey) {
            #if canImport(UIKit)
            if isFocused, hasVideo {
                setupPlayer()
            } else {
                teardownPlayer()
            }
            #endif
        }
        .onDisappear {
            #if canImport(UIKit)
            teardownPlayer()
            #endif
        }
    }

    /// Stable key for `.task(id:)` — re-runs the player setup whenever
    /// either the focused state OR the post id changes (LazyHStack can
    /// recycle a card view onto a different post during fast scroll).
    private var focusKey: String { "\(post.id):\(isFocused)" }

    #if canImport(UIKit)
    private func setupPlayer() {
        guard let data = post.videoData else { return }
        // Tear down any previous player before allocating a new one
        // (covers fast-scroll edge cases where the same card binds to a
        // new post without a teardown in between).
        teardownPlayer()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(post.id.uuidString).rail.mp4")
        if !FileManager.default.fileExists(atPath: tempURL.path) {
            try? data.write(to: tempURL)
        }

        let avPlayer = AVPlayer(url: tempURL)
        avPlayer.isMuted = true
        avPlayer.actionAtItemEnd = .none
        avPlayer.play()

        // Loop on end-of-playback so the preview keeps moving.
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            avPlayer.seek(to: .zero)
            avPlayer.play()
        }

        player = avPlayer
    }

    private func teardownPlayer() {
        if let observer = loopObserver {
            NotificationCenter.default.removeObserver(observer)
            loopObserver = nil
        }
        player?.pause()
        player = nil
    }
    #endif

    @ViewBuilder
    private var cover: some View {
        #if canImport(UIKit)
        if let data = coverData(), let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 260, height: 360)
                .clipped()
        } else {
            // Fallback gradient + dumbbell glyph for posts without media
            ZStack {
                LinearGradient(
                    colors: [GQColors.deepBlue.opacity(0.4), GQColors.vividPurple.opacity(0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        #else
        Color.gray
        #endif
    }
}

// MARK: - Auto-advance Progress Bar

/// Lifted from `ExploreHeroCard` so the rail keeps the same forward-
/// motion cadence the existing hero already has. Parent re-keys this
/// view via `.id(currentIndex)` so each pick resets the fill cleanly.
private struct HeroProgressBar: View {
    let duration: Double
    let active: Bool
    let onComplete: () -> Void

    @State private var progress: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(GQGradients.primary.opacity(0.10))
                Rectangle()
                    .fill(GQGradients.primary)
                    .frame(width: geo.size.width * CGFloat(progress))
                    .animation(.linear(duration: duration), value: progress)
            }
        }
        .frame(height: 3)
        .clipShape(RoundedRectangle(cornerRadius: 1.5))
        .task {
            guard active else { return }
            progress = 1
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if !Task.isCancelled { onComplete() }
        }
    }
}
