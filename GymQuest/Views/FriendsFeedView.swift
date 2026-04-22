import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

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
                        .padding(.top, 2)
                        .padding(.bottom, 6)
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
            .refreshable {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                refreshTick &+= 1
                // Small delay gives the native refresh spinner time to
                // register so the gesture feels real — @Query data is
                // already live, nothing else to fetch.
                try? await Task.sleep(for: .milliseconds(650))
            }
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
    /// candidate pool for "Suggested for You" interstitials. Prioritized
    /// by club co-membership so the content feels contextually close.
    private var suggestedPosts: [Post] {
        let followedIds = Set(follows.filter { $0.userId == profile.id }.map(\.odId))
        let myClubIds = Set(clubs.filter { $0.memberIds.contains(profile.id) }.map(\.id))
        let clubMemberIds = Set(clubs
            .filter { myClubIds.contains($0.id) }
            .flatMap { $0.memberIds })
            .subtracting(followedIds)
            .subtracting([profile.id])

        return allPosts
            .filter { post in
                !followedIds.contains(post.authorId)
                && post.authorId != profile.id
                && (post.photoData != nil || post.videoData != nil || !post.mediaItems.isEmpty)
            }
            .sorted { a, b in
                // In-club authors first, then by timestamp
                let aIn = clubMemberIds.contains(a.authorId)
                let bIn = clubMemberIds.contains(b.authorId)
                if aIn != bIn { return aIn && !bIn }
                return a.timestamp > b.timestamp
            }
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

        // Normal: friend posts with periodic suggestion interstitials
        var suggestedIter = suggested.makeIterator()
        var peopleCursor = 0
        for (i, post) in friend.enumerated() {
            items.append(.post(post))
            // Every 4 posts, a suggested post (if pool has any left)
            if (i + 1) % 4 == 0, let next = suggestedIter.next() {
                items.append(.suggestedPost(next))
            }
            // Every 6 posts, a people card (if pool has any left)
            if (i + 1) % 6 == 0 {
                let next = peopleSlice(peopleCursor)
                if !next.isEmpty {
                    items.append(.suggestedPeople(next))
                    peopleCursor += 4
                }
            }
        }

        return items
    }

    private var suggestedPostBanner: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
            Text("SUGGESTED FOR YOU")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
            Spacer(minLength: 0)
        }
        .foregroundStyle(GQGradients.primary)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(GQColors.surfaceBase)
    }

    /// Horizontal card of suggested people to follow — fills in when
    /// the feed might otherwise feel thin. Appears in both cold-start
    /// and mid-feed positions.
    @ViewBuilder
    private func suggestedPeopleCard(_ people: [UserProfile]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
                Text("PEOPLE YOU MIGHT KNOW")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(GQColors.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(people) { person in
                        suggestedPersonMiniCard(person)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .background(GQColors.surfaceBase)
    }

    /// 140pt-wide vertical card used in the horizontal people rail —
    /// avatar, name, username, inline Follow button.
    @ViewBuilder
    private func suggestedPersonMiniCard(_ person: UserProfile) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(GQGradients.primary)
                    .frame(width: 52, height: 52)
                Text(String(person.name.prefix(1)).uppercased())
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            VStack(spacing: 1) {
                Text(person.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                if !person.username.isEmpty {
                    Text("@\(person.username)")
                        .font(.system(size: 10))
                        .foregroundColor(GQColors.textTertiary)
                        .lineLimit(1)
                }
            }
            Button {
                followUser(person)
            } label: {
                Text("Follow")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(GQGradients.primary))
            }
            .buttonStyle(.plain)
        }
        .frame(width: 126)
        .padding(10)
        .background(GQColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(GQColors.borderDefault.opacity(0.7), lineWidth: 0.5)
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
