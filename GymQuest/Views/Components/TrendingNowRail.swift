import SwiftUI
import AVKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - TodaysMixWatchedStore

/// Per-day record of which rail picks the user has actually opened.
/// Resets at local midnight by being keyed on the day-string — yesterday's
/// list is dropped automatically the first time we read a new day.
///
/// Used by:
/// - The rail page dots, to mark watched picks distinctly.
/// - The Today's Mix sequence player, to show the "X of N" completion
///   line on the end-of-mix card.
enum TodaysMixWatchedStore {
    private static let key = "gq_todays_mix_watched_v1"
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static var todayKey: String {
        dayFormatter.string(from: Date())
    }

    /// All post ids the user has opened from the rail today.
    static func watchedToday() -> Set<UUID> {
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        let raw = stored[todayKey] ?? []
        return Set(raw.compactMap { UUID(uuidString: $0) })
    }

    static func markWatched(_ postId: UUID) {
        var stored = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        // Drop yesterday's keys so the dictionary doesn't grow forever.
        stored = stored.filter { $0.key == todayKey }
        var todays = Set(stored[todayKey] ?? [])
        todays.insert(postId.uuidString)
        stored[todayKey] = Array(todays)
        UserDefaults.standard.set(stored, forKey: key)
    }

    static func isWatched(_ postId: UUID) -> Bool {
        watchedToday().contains(postId)
    }

    /// "Resets in 8h" / "Resets in 47m" — short label for the rail
    /// header pill. Always rounds up to the nearest minute so the user
    /// never sees "Resets in 0m" when there's still time left.
    static func resetCountdown(now: Date = Date()) -> String {
        let cal = Calendar.current
        let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now)
        let interval = max(0, tomorrow.timeIntervalSince(now))
        let totalMinutes = Int(ceil(interval / 60))
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            return "Resets in \(hours)h"
        }
        return "Resets in \(totalMinutes)m"
    }
}

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
    /// Set of post IDs the user has opened from the rail today.
    /// Refreshed via `.task` on appear and re-pulled when the rail
    /// is shown again (cheap UserDefaults read).
    @State private var watchedToday: Set<UUID> = []
    /// Refreshed every minute by a 60s timer so the "resets in 8h"
    /// pill counts down without the user having to leave the page.
    @State private var resetLabel: String = TodaysMixWatchedStore.resetCountdown()
    private let countdownTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

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
            watchedToday = TodaysMixWatchedStore.watchedToday()
            resetLabel = TodaysMixWatchedStore.resetCountdown()
        }
        .onReceive(countdownTimer) { _ in
            resetLabel = TodaysMixWatchedStore.resetCountdown()
            // Re-pull watched in case the user's been in the mix view
            // and their list grew since the last appear.
            watchedToday = TodaysMixWatchedStore.watchedToday()
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
            Text("TODAY'S MIX")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(GQColors.textTertiary)
            Text("·")
                .font(.system(size: 11))
                .foregroundColor(GQColors.textTertiary)
            Text(resetLabel)
                .font(.system(size: 11, weight: .medium))
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
                            TodaysMixWatchedStore.markWatched(post.id)
                            watchedToday = TodaysMixWatchedStore.watchedToday()
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
                let watched = watchedToday.contains(picks[i].id)
                Capsule()
                    .fill(dotFill(forIndex: i, watched: watched))
                    .frame(width: i == currentIndex ? 18 : 5, height: 5)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: currentIndex)
            }
            Spacer()
        }
    }

    /// Three states for each dot:
    /// 1. Current (selected) → filled brand gradient, longer width
    /// 2. Watched (already opened today) → solid mid-tone
    /// 3. Unwatched → faint adaptive overlay (existing default)
    private func dotFill(forIndex i: Int, watched: Bool) -> AnyShapeStyle {
        if i == currentIndex {
            return AnyShapeStyle(GQGradients.primary)
        }
        if watched {
            return AnyShapeStyle(GQColors.textTertiary.opacity(0.6))
        }
        return AnyShapeStyle(GQColors.adaptiveOverlay(0.18))
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

    // MARK: - Live Signal

    /// Decoded freshness/popularity signal shown as a top-left chip.
    /// Priority (highest first): just-posted (<5m), very-recent (<1h),
    /// popular-today (viewCount), trending (engagementScore). nil when
    /// none apply so the chip doesn't show.
    private var liveSignal: LiveSignal? {
        let elapsed = Date().timeIntervalSince(post.timestamp)
        if elapsed < 300 {
            return .justPosted
        }
        if elapsed < 3600 {
            return .recent(minutes: Int(elapsed / 60))
        }
        if post.viewCount >= 100 {
            return .views(post.viewCount)
        }
        if post.engagementScore >= 0.5 {
            return .trending
        }
        return nil
    }

    private enum LiveSignal {
        case justPosted
        case recent(minutes: Int)
        case views(Int)
        case trending
    }

    @ViewBuilder
    private func liveChip(_ signal: LiveSignal) -> some View {
        switch signal {
        case .justPosted:
            HStack(spacing: 5) {
                PulsingDot(color: GQColors.success)
                Text("JUST POSTED")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.black.opacity(0.55)))
        case .recent(let minutes):
            chipShell(text: "\(minutes)m ago", icon: "clock.fill")
        case .views(let n):
            chipShell(text: formatViews(n), icon: "eye.fill")
        case .trending:
            chipShell(text: "TRENDING", icon: "flame.fill", tracking: 0.5, weight: .bold)
        }
    }

    @ViewBuilder
    private func chipShell(text: String, icon: String, tracking: CGFloat = 0.0, weight: Font.Weight = .semibold) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 8, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: weight))
                .tracking(tracking)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.black.opacity(0.55)))
    }

    private func formatViews(_ n: Int) -> String {
        if n >= 1000 {
            let k = Double(n) / 1000.0
            return String(format: "%.1fK views", k)
        }
        return "\(n) views"
    }

    // MARK: - Title / Author

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

            // Top row — live-signal chip on the left (freshness /
            // trending / view count) and workout-type chip on the
            // right. Both sit above the bottom gradient and only pin
            // to the top edge so the bottom caption stays roomy.
            VStack {
                HStack(alignment: .top) {
                    if let signal = liveSignal {
                        liveChip(signal)
                    }
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

// MARK: - Pulsing Dot

/// Small colored dot that pulses opacity to imply liveness — used on
/// the JUST POSTED chip so the top-left signal reads as motion even
/// when the rail is paused.
private struct PulsingDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(pulse ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
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
