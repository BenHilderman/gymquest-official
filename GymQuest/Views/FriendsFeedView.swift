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
        ScrollView {
            LazyVStack(spacing: 0) {
                // Presence strip — moved here from Discover so the Friends
                // tab owns "who's live / who posted recently" in one place.
                if !friendsMembers.isEmpty {
                    FriendsRow(
                        members: friendsMembers,
                        onTapMember: { _ in /* scroll to post — no-op for now */ },
                        onStartWorkout: { dismiss() }
                    )
                    .padding(.top, 8)

                    Rectangle()
                        .fill(GQColors.borderSubtle)
                        .frame(height: 1)
                        .padding(.top, 10)
                }

                if friendPosts.isEmpty {
                    emptyState
                } else {
                    ForEach(Array(friendPosts.enumerated()), id: \.element.id) { index, post in
                        PostCardV2(
                            post: post,
                            currentUserId: profile.id,
                            currentUserName: profile.name,
                            profile: profile
                        )

                        Rectangle()
                            .fill(GQColors.borderSubtle)
                            .frame(height: 1)

                        // Clean scroll — no interrupts
                    }

                    backToTrainingFooter
                }
            }
            .padding(.bottom, 100)
        }
        .scrollContentBackground(.hidden)
        .gqPageBackground()
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
                        .background(Circle().fill(Color.red))
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

    /// People from the user's clubs they don't yet follow. Max 8. Used to
    /// fill a quiet Friends feed with actionable "add someone" rows instead
    /// of a dead-end placeholder.
    private var suggestedFromClubs: [UserProfile] {
        let myClubs = clubs.filter { $0.memberIds.contains(profile.id) }
        guard !myClubs.isEmpty else { return [] }
        let followedIds = Set(follows.filter { $0.userId == profile.id }.map(\.odId))
        let clubMemberIds = Set(myClubs.flatMap { $0.memberIds }).subtracting([profile.id])
        let candidateIds = clubMemberIds.subtracting(followedIds)
        return allUserProfiles
            .filter { candidateIds.contains($0.id) }
            .prefix(8)
            .map { $0 }
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
