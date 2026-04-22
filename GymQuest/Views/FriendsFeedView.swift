import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// LCG-backed RandomNumberGenerator seeded by the refresh tick. Used to
/// shuffle suggestion pools so pull-to-refresh surfaces different picks.
/// Deterministic within a session — identical seeds reproduce the same
/// order, so SwiftUI view identity stays stable between re-renders.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state = state &* 2862933555777941757 &+ 3037000493
        return state
    }
}

/// The cozy friends-only scroll — exact same rendering as the original
/// Friends tab (PostCardV2 + FeedCurator). Presented as a sheet from
/// Explore. Every ~6 posts a workout suggestion card appears.
struct FriendsFeedView: View {
    let profile: UserProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState

    @Query(sort: \Post.timestamp, order: .reverse) private var allPosts: [Post]
    @Query private var follows: [Friend]
    @Query private var presenceStates: [UserPresenceState]
    @Query private var allUserProfiles: [UserProfile]
    @Query private var likes: [Like]
    @Query private var comments: [Comment]
    @Query private var clubs: [Club]

    @State private var presentingActivity: Bool = false
    /// Tick that advances once a minute so times in the presence strip
    /// ("Push · 6m") stay current without a full app refresh. Referenced
    /// in friendsMembers so SwiftUI invalidates the computed list each
    /// tick and the builder re-runs with a fresh Date().
    @State private var minuteTick: Date = Date()
    /// Incremented on pull-to-refresh so the mixedFeed recomputes
    /// (different suggested-post selection, re-shuffled people card).
    @State private var refreshTick: Int = 0
    /// Friend-post count observed at the last refresh — when a refresh
    /// doesn't yield new friend content we lean harder on suggestions
    /// and show a "No new posts" toast instead of looking broken.
    @State private var lastRefreshFriendCount: Int = 0
    /// Consecutive refreshes that returned no new friend posts. Drives
    /// how aggressively we pad the feed with trending/recommended.
    @State private var staleRefreshCount: Int = 0
    /// Ephemeral toast shown at the top of the feed after a refresh.
    @State private var refreshToast: String? = nil
    private let minuteTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// UserDefaults key holding the timestamp of the last Activity view
    /// for this user. Anything newer is counted as unread on the bell icon.
    private var lastActivitySeenKey: String { "activity_last_seen_\(profile.id.uuidString)" }
    private var lastActivitySeen: Date {
        let t = UserDefaults.standard.double(forKey: lastActivitySeenKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : .distantPast
    }

    /// Count of likes + comments on the user's posts since the user last
    /// opened the Activity sheet. Drives the red badge on the bell icon.
    private var unreadActivityCount: Int {
        let myPostIds = Set(allPosts.filter { $0.authorId == profile.id }.map(\.id))
        let since = lastActivitySeen
        let newLikes = likes.filter { myPostIds.contains($0.postId) && $0.userId != profile.id && $0.timestamp > since }.count
        let newComments = comments.filter { myPostIds.contains($0.postId) && $0.authorId != profile.id && $0.timestamp > since }.count
        return newLikes + newComments
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let toast = refreshToast {
                        refreshToastBanner(toast)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if unreadActivityCount > 0 {
                        unreadActivityBanner
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 4)
                    }

                    if !friendsMembers.isEmpty {
                        // Presence strip lives on the page color, not
                        // surfaceBase — makes it a distinct utility
                        // band above the feed so it doesn't blend into
                        // the first post below.
                        FriendsRow(
                            members: friendsMembers,
                            onTapMember: { member in
                                if let target = friendPosts.first(where: { $0.authorId == member.id }) {
                                    #if canImport(UIKit)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                    withAnimation(.easeInOut(duration: 0.35)) {
                                        proxy.scrollTo(target.id, anchor: .top)
                                    }
                                }
                            },
                            onStartWorkout: { dismiss() }
                        )
                        .padding(.top, 0)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity)
                        .background(GQColors.background)
                    }

                    let feed = mixedFeed
                    if feed.isEmpty {
                        emptyState
                    } else {
                        // Continuous surface with borderProminent
                        // hairlines between items. Items include friend
                        // posts, 'SUGGESTED FOR YOU' posts from clubs,
                        // and 'People You Might Know' horizontal cards
                        // — interleaved so the feed stays fresh.
                        ForEach(Array(feed.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Rectangle()
                                    .fill(GQColors.borderProminent)
                                    .frame(height: 1)
                            }

                            switch item {
                            case .post(let post):
                                PostCardV2(
                                    post: post,
                                    currentUserId: profile.id,
                                    currentUserName: profile.name,
                                    profile: profile
                                )
                                .id(post.id)
                            case .suggestedPost(let post):
                                VStack(spacing: 0) {
                                    suggestedPostBanner
                                    PostCardV2(
                                        post: post,
                                        currentUserId: profile.id,
                                        currentUserName: profile.name,
                                        profile: profile
                                    )
                                    .id(post.id)
                                }
                            case .suggestedPeople(let people):
                                suggestedPeopleCard(people)
                            }
                        }

                        backToTrainingFooter
                    }
                }
                .padding(.bottom, 100)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .background(GQColors.surfaceBase)
            .refreshable { await performRefresh() }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(GQColors.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavAvatarButton(profile: profile)
            }
            ToolbarItem(placement: .topBarTrailing) {
                activityBellButton
            }
        }
        .sheet(isPresented: $presentingActivity, onDismiss: markActivitySeen) {
            NavigationStack {
                SocialActivityView(profile: profile)
            }
        }
        .onReceive(minuteTimer) { now in
            minuteTick = now
        }
    }

    private var unreadActivityBanner: some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            presentingActivity = true
        } label: {
            // Compact single-line pill instead of a full card with
            // icon + two lines + chevron. Less chrome above the feed.
            HStack(spacing: 8) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
                Text(bannerHeadline)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(GQColors.background)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var bannerHeadline: String {
        let n = unreadActivityCount
        if n == 1 { return "1 new like or comment" }
        if n > 9 { return "9+ new likes and comments" }
        return "\(n) new likes and comments"
    }

    private var activityBellButton: some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            presentingActivity = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(GQColors.textPrimary)
                    .frame(width: 32, height: 32)

                if unreadActivityCount > 0 {
                    Text(unreadActivityCount > 9 ? "9+" : "\(unreadActivityCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Circle().fill(GQGradients.primary))
                        .offset(x: 2, y: -2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func markActivitySeen() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastActivitySeenKey)
    }

    // MARK: - Data

    private var friendPosts: [Post] {
        let followedIds = Set(follows.filter { $0.userId == profile.id }.map(\.odId))
        return allPosts.filter {
            followedIds.contains($0.authorId) &&
            ($0.photoData != nil || $0.videoData != nil || !$0.mediaItems.isEmpty)
        }
    }

    private var friendsMembers: [FriendsMember] {
        // Read minuteTick so SwiftUI registers this computed as
        // dependent on the timer — "Push · 6m" becomes "Push · 7m"
        // automatically as the minute rolls over, and the avatar row
        // re-sorts when someone starts/ends a session.
        _ = minuteTick
        let followedIds = Set(follows.filter { $0.userId == profile.id }.map(\.odId))
        let liveNow = PresenceService.liveNow(
            from: presenceStates,
            selfId: profile.id,
            followedIds: followedIds
        )
        let profilesById = Dictionary(uniqueKeysWithValues: allUserProfiles.map { ($0.id, $0) })
        return FriendsMemberBuilder.build(
            selfId: profile.id,
            follows: follows,
            allPosts: allPosts,
            liveNowStates: liveNow,
            profilesById: profilesById
        )
    }

    private var bestSuggestion: Post? {
        allPosts
            .filter { $0.sharedWorkoutData != nil }
            .max(by: { $0.doabilityScore < $1.doabilityScore })
    }

    // MARK: - Workout suggestion

    private func workoutSuggestionCard(_ post: Post) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(GQGradients.primary.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(suggestionTitle(post))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                if let dur = post.duration, dur > 0 {
                    Text("\(dur) min · \(post.workoutType?.capitalized ?? "Workout")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(GQColors.textSecondary)
                }
            }

            Spacer()

            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let data = post.sharedWorkoutData,
                       let shared = try? JSONDecoder().decode(SharedWorkoutData.self, from: data) {
                        let type = WorkoutType(rawValue: shared.workoutType) ?? .push
                        appState.startWorkout(type: type, exercises: shared.toActiveExercises(), customTitle: shared.title)
                    }
                }
            } label: {
                Text("Try it →")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(GQGradients.primary))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .homeSocialCard(cornerRadius: 14)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func suggestionTitle(_ post: Post) -> String {
        if let data = post.sharedWorkoutData,
           let shared = try? JSONDecoder().decode(SharedWorkoutData.self, from: data),
           !shared.title.isEmpty { return shared.title }
        return post.exerciseHighlight ?? post.workoutType?.capitalized ?? "Workout"
    }

    // MARK: - Weekly prompt (from original socialFeedContent)

    private func weeklyPromptRow(label: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(GQGradients.primary)
                .frame(width: 40, height: 40)
                .background(GQColors.deepBlue.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Text("Tap to log your session")
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
            }
            Spacer()
        }
        .padding(14)
        .background(GQColors.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(GQColors.borderDefault, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Empty + footer

    /// People from the user's clubs they don't yet follow. Used to seed
    /// both the "People You Might Know" interstitial cards in the main
    /// feed and the empty-state suggestions.
    private var suggestedFromClubs: [UserProfile] {
        let myClubs = clubs.filter { $0.memberIds.contains(profile.id) }
        guard !myClubs.isEmpty else { return [] }
        let followedIds = Set(follows.filter { $0.userId == profile.id }.map(\.odId))
        let clubMemberIds = Set(myClubs.flatMap { $0.memberIds }).subtracting([profile.id])
        let candidateIds = clubMemberIds.subtracting(followedIds)
        return allUserProfiles
            .filter { candidateIds.contains($0.id) }
            .prefix(20)
            .map { $0 }
    }

    // MARK: - Mixed feed (friends + suggestions interleaved)

    /// Recent posts with media from people the user does NOT follow —
    /// candidate pool for "Suggested for You" interstitials.
    ///
    /// Ordering strategy:
    /// 1. Engagement score (likes + comments × 2) — trending content first
    /// 2. Club co-membership — friends-of-friends signal
    /// 3. Recency — break ties
    ///
    /// On pull-to-refresh, the pool is re-shuffled within buckets so
    /// each refresh surfaces different picks.
    private var suggestedPosts: [Post] {
        let followedIds = Set(follows.filter { $0.userId == profile.id }.map(\.odId))
        let myClubIds = Set(clubs.filter { $0.memberIds.contains(profile.id) }.map(\.id))
        let clubMemberIds = Set(clubs
            .filter { myClubIds.contains($0.id) }
            .flatMap { $0.memberIds })
            .subtracting(followedIds)
            .subtracting([profile.id])

        // Pre-compute engagement counts so the sort is O(n log n) not
        // O(n² × likes).
        let likeCountByPost = Dictionary(grouping: likes, by: \.postId).mapValues(\.count)
        let commentCountByPost = Dictionary(grouping: comments, by: \.postId).mapValues(\.count)

        var pool = allPosts
            .filter { post in
                !followedIds.contains(post.authorId)
                && post.authorId != profile.id
                && (post.photoData != nil || post.videoData != nil || !post.mediaItems.isEmpty)
            }
            .sorted { a, b in
                let aEngagement = (likeCountByPost[a.id] ?? 0) + (commentCountByPost[a.id] ?? 0) * 2
                let bEngagement = (likeCountByPost[b.id] ?? 0) + (commentCountByPost[b.id] ?? 0) * 2
                if aEngagement != bEngagement { return aEngagement > bEngagement }
                let aIn = clubMemberIds.contains(a.authorId)
                let bIn = clubMemberIds.contains(b.authorId)
                if aIn != bIn { return aIn && !bIn }
                return a.timestamp > b.timestamp
            }

        if refreshTick > 0, pool.count > 1 {
            var rng = SeededGenerator(seed: UInt64(refreshTick))
            // Shuffle in chunks of 4 so the top-trending bucket stays
            // top-ish but with different picks each refresh, rather
            // than rearranging the whole list and burying everything.
            let chunkSize = 4
            var shuffled: [Post] = []
            var index = pool.startIndex
            while index < pool.endIndex {
                let end = pool.index(index, offsetBy: chunkSize, limitedBy: pool.endIndex) ?? pool.endIndex
                var chunk = Array(pool[index..<end])
                chunk.shuffle(using: &rng)
                shuffled.append(contentsOf: chunk)
                index = end
            }
            pool = shuffled
        }
        return pool
    }

    /// How aggressively to lean on suggestions. 1 = default cadence
    /// (suggested every 4 friend posts, people every 6). Rises after
    /// consecutive stale refreshes OR when the user follows very few
    /// people, so the feed never looks empty.
    private var suggestionBoost: Int {
        var b = 1
        if friendPosts.count < 3 { b += 1 }
        if staleRefreshCount >= 2 { b += 1 }
        return min(b, 3)
    }

    // MARK: - Refresh handler

    /// Runs when the user swipes down from the top. Bumps refreshTick,
    /// detects whether any new friend posts arrived since the last
    /// pull, and either shows a "new posts" toast or falls through to
    /// a "showing trending" toast with heavier suggestion density.
    @MainActor
    private func performRefresh() async {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        // Let the spinner animate for a beat so the gesture feels real.
        try? await Task.sleep(for: .milliseconds(700))

        let currentCount = friendPosts.count
        let hadNewFriendPosts = currentCount > lastRefreshFriendCount

        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            refreshTick &+= 1
            if hadNewFriendPosts {
                staleRefreshCount = 0
                let delta = currentCount - lastRefreshFriendCount
                refreshToast = delta == 1 ? "1 new post" : "\(delta) new posts"
            } else {
                staleRefreshCount += 1
                refreshToast = "No new posts — showing trending"
            }
            lastRefreshFriendCount = currentCount
        }

        // Auto-dismiss the toast after a few seconds.
        try? await Task.sleep(for: .seconds(3))
        withAnimation(.easeOut(duration: 0.25)) {
            refreshToast = nil
        }
    }

    /// Compact toast shown after a pull-to-refresh — either "N new
    /// posts" or "No new posts — showing trending". Auto-dismisses.
    @ViewBuilder
    private func refreshToastBanner(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(GQGradients.primary)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(GQColors.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(GQColors.background)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(GQColors.borderDefault.opacity(0.5), lineWidth: 0.5)
        )
    }

    enum FeedItem: Identifiable {
        case post(Post)
        case suggestedPost(Post)
        case suggestedPeople([UserProfile])

        var id: String {
            switch self {
            case .post(let p): return "post-\(p.id.uuidString)"
            case .suggestedPost(let p): return "sugp-\(p.id.uuidString)"
            case .suggestedPeople(let people):
                return "people-\(people.first?.id.uuidString ?? "empty")-\(people.count)"
            }
        }
    }

    /// The rendered feed — interleaves friend posts, suggested non-
    /// friend posts, and "People You Might Know" cards. Cold-start
    /// (user follows nobody) falls back to a suggestion-led feed so
    /// the page is never empty.
    private var mixedFeed: [FeedItem] {
        _ = refreshTick

        let friend = friendPosts
        let suggested = Array(suggestedPosts.prefix(12))
        let peoplePool = suggestedFromClubs

        // Partition people into slices of 4 so each interstitial card
        // shows fresh faces.
        func peopleSlice(_ startIndex: Int) -> [UserProfile] {
            guard startIndex < peoplePool.count else { return [] }
            let end = min(peoplePool.count, startIndex + 4)
            return Array(peoplePool[startIndex..<end])
        }

        var items: [FeedItem] = []

        if friend.isEmpty {
            // Cold-start: lead with a people card + suggested posts
            if let slice = Optional(peopleSlice(0)), !slice.isEmpty {
                items.append(.suggestedPeople(slice))
            }
            var peopleCursor = 4
            for (i, post) in suggested.enumerated() {
                items.append(.suggestedPost(post))
                if (i + 1) % 3 == 0 {
                    let next = peopleSlice(peopleCursor)
                    if !next.isEmpty {
                        items.append(.suggestedPeople(next))
                        peopleCursor += 4
                    }
                }
            }
            return items
        }

        // Normal: friend posts with periodic suggestion interstitials.
        // Cadence tightens when suggestionBoost > 1 (few friends and/or
        // stale refreshes).
        let boost = suggestionBoost
        let suggestedEvery = max(2, 5 - boost)   // 4, 3, 2 as boost rises
        let peopleEvery = max(4, 7 - boost)      // 6, 5, 4 as boost rises
        var suggestedIter = suggested.makeIterator()
        var peopleCursor = 0
        for (i, post) in friend.enumerated() {
            items.append(.post(post))
            if (i + 1) % suggestedEvery == 0, let next = suggestedIter.next() {
                items.append(.suggestedPost(next))
            }
            if (i + 1) % peopleEvery == 0 {
                let next = peopleSlice(peopleCursor)
                if !next.isEmpty {
                    items.append(.suggestedPeople(next))
                    peopleCursor += 4
                }
            }
        }

        // If staleRefreshCount is high (user refreshed multiple times
        // with no new friend content), pad the tail with more trending
        // suggestions so the feed always shows fresh content after a
        // refresh.
        if staleRefreshCount >= 1 {
            while let next = suggestedIter.next() {
                items.append(.suggestedPost(next))
            }
        }

        return items
    }

    private var suggestedPostBanner: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .bold))
            Text("SUGGESTED FOR YOU")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
            Spacer(minLength: 0)
        }
        .foregroundStyle(GQGradients.primary)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 3)
        .background(GQColors.surfaceBase)
    }

    /// Horizontal card of suggested people to follow — fills in when
    /// the feed might otherwise feel thin. Appears in both cold-start
    /// and mid-feed positions.
    @ViewBuilder
    private func suggestedPeopleCard(_ people: [UserProfile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
                Text("PEOPLE YOU MIGHT KNOW")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(GQColors.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(people) { person in
                        suggestedPersonMiniCard(person)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .background(GQColors.surfaceBase)
    }

    /// Compact vertical card used in the horizontal people rail —
    /// avatar, name, Follow button. Username dropped to save vertical
    /// space; tap the card in a later pass to view profile.
    @ViewBuilder
    private func suggestedPersonMiniCard(_ person: UserProfile) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(GQGradients.primary)
                    .frame(width: 42, height: 42)
                Text(String(person.name.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            Text(person.name.components(separatedBy: " ").first ?? person.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(GQColors.textPrimary)
                .lineLimit(1)

            Button {
                followUser(person)
            } label: {
                Text("Follow")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(GQGradients.primary))
            }
            .buttonStyle(.plain)
        }
        .frame(width: 106)
        .padding(8)
        .background(GQColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(GQColors.borderDefault.opacity(0.6), lineWidth: 0.5)
        )
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                Image(systemName: "person.2")
                    .font(.system(size: 36))
                    .foregroundStyle(GQGradients.primary)
                Text("Quiet on the feed")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Text(suggestedFromClubs.isEmpty
                     ? "Follow people to see their workouts here"
                     : "Follow people from your clubs to fill it up")
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(.top, 40)

            if !suggestedFromClubs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("FROM YOUR CLUBS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(GQColors.textTertiary)
                        .tracking(0.6)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    LazyVStack(spacing: 8) {
                        ForEach(suggestedFromClubs) { person in
                            suggestedPersonRow(person)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .padding(.bottom, 24)
    }

    private func suggestedPersonRow(_ person: UserProfile) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(GQGradients.primary).frame(width: 40, height: 40)
                Text(String(person.name.prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                if !person.username.isEmpty {
                    Text("@\(person.username)")
                        .font(.system(size: 11))
                        .foregroundColor(GQColors.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                followUser(person)
            } label: {
                Text("Follow")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(GQGradients.primary))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .homeSocialCard(cornerRadius: 12)
    }

    private func followUser(_ person: UserProfile) {
        let friend = Friend(
            userId: profile.id,
            odId: person.id,
            odName: person.name,
            odUsername: person.username
        )
        modelContext.insert(friend)
        try? modelContext.save()
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    private var backToTrainingFooter: some View {
        VStack(spacing: 10) {
            Text("You've seen your friends' latest")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(GQColors.textTertiary)
            Button { dismiss() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 13, weight: .bold))
                    Text("Back to training")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(GQGradients.primary))
                .padding(.horizontal, 40)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 16)
    }
}
