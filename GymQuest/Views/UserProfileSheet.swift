import SwiftUI
import SwiftData
import Supabase

struct UserProfileSheet: View {
    let userId: UUID
    let currentProfile: UserProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allProfiles: [UserProfile]
    @Query private var allPosts: [Post]
    @Query private var allFriends: [Friend]

    @State private var isFollowing = false
    /// Forces a re-render after toggling AutoReactStore (UserDefaults isn't observable).
    @State private var autoReactTick: Int = 0
    /// Same — forces re-render after flipping LocationTrustedFriendsStore.
    @State private var locationTrustTick: Int = 0
    /// Soft prompt shown the moment the user follows: "Show [Name] my gym?"
    @State private var showLocationTrustPrompt: Bool = false
    @Query private var profileSheetReactions: [LiveReaction]

    private var userProfile: UserProfile? {
        allProfiles.first { $0.id == userId }
    }

    private var userPosts: [Post] {
        allPosts.filter { $0.authorId == userId }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var followerCount: Int {
        userProfile?.followerCount ?? 0
    }

    private var followingCount: Int {
        userProfile?.followingCount ?? 0
    }

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    profileHeader
                    statsRow
                    followButton
                    if userId != currentProfile.id {
                        aliveFriendActions
                    }
                    postsGrid
                }
                .padding(.top, 20)
            }
            .background(GQColors.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(GQColors.textTertiary)
                    }
                }
            }
            .onAppear { loadFollowState() }
            .sheet(isPresented: $showLocationTrustPrompt) {
                locationTrustSoftPromptSheet
                    .presentationDetents([.height(220)])
            }
        }
    }

    @ViewBuilder
    private var locationTrustSoftPromptSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule().fill(GQColors.borderDefault).frame(width: 36, height: 4).padding(.top, 8)
                .frame(maxWidth: .infinity)
            Text("Show \(firstName) your gym?")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(GQColors.textPrimary)
            Text("They'll see when you're at a saved gym. Strangers never see this. You can change it anytime in their profile.")
                .font(.system(size: 13))
                .foregroundColor(GQColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    showLocationTrustPrompt = false
                } label: {
                    Text("Not now")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(GQColors.surfaceBase))
                        .overlay(Capsule().stroke(GQColors.borderDefault, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                Button {
                    LocationTrustedFriendsStore.add(userId)
                    locationTrustTick &+= 1
                    showLocationTrustPrompt = false
                } label: {
                    Text("Show \(firstName)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(GQGradients.primary))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .background(GQColors.background)
    }

    // MARK: - Header

    @ViewBuilder
    private var profileHeader: some View {
        VStack(spacing: 8) {
            // Avatar with universal presence ring (Alive Phase 1).
            Group {
                #if canImport(UIKit)
                if let data = userProfile?.profilePhotoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(Circle())
                } else {
                    avatarCircle
                }
                #else
                avatarCircle
                #endif
            }
            .presenceRing(userId, size: 80)

            Text(userProfile?.name ?? "Unknown")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(GQColors.textPrimary)

            Text("@\(userProfile?.username ?? "")")
                .font(.system(size: 14))
                .foregroundColor(GQColors.textSecondary)
        }
    }

    private var avatarCircle: some View {
        Circle()
            .fill(GQGradients.primary)
            .frame(width: 80, height: 80)
            .overlay(
                Text(String((userProfile?.name ?? "?").prefix(1)).uppercased())
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            )
    }

    // MARK: - Stats

    // Viewing another user: no follower/following counts — the memo's comparison-machine
    // ban. Just show how many posts they've shared. Their own profile keeps the rest.
    private var statsRow: some View {
        HStack(spacing: 0) {
            statColumn(value: "\(userPosts.count)", label: userPosts.count == 1 ? "Post" : "Posts")
        }
        .padding(.horizontal, 16)
    }

    private func statColumn(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(GQColors.textPrimary)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(GQColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Follow Button

    @ViewBuilder
    private var followButton: some View {
        if userId != currentProfile.id {
            Button {
                toggleFollow()
            } label: {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isFollowing ? GQColors.textPrimary : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        Group {
                            if isFollowing {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.clear)
                            } else {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(GQGradients.primary)
                            }
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isFollowing ? GQColors.borderSubtle : Color.clear, lineWidth: 1)
                    )
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Posts Grid

    @ViewBuilder
    private var postsGrid: some View {
        if userPosts.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "camera")
                    .font(.system(size: 32))
                    .foregroundColor(GQColors.textTertiary)
                Text("No posts yet")
                    .font(.system(size: 14))
                    .foregroundColor(GQColors.textSecondary)
            }
            .padding(.top, 40)
        } else {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(userPosts) { post in
                    ProfilePostThumbnail(post: post)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Alive friend actions (auto-react / quick replies / streak badge)

    @ViewBuilder
    private var aliveFriendActions: some View {
        VStack(spacing: 10) {
            // Per-friend asymmetric location trust toggle. Adding this
            // friend → they see my gym name when I'm there. Asymmetric:
            // their trust list is independent.
            Button {
                LocationTrustedFriendsStore.toggle(userId)
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                locationTrustTick &+= 1
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: locationTrustOn ? "checkmark.circle.fill" : "mappin.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(locationTrustOn ? AnyShapeStyle(AlivePresence.green) : AnyShapeStyle(GQGradients.primary))
                    Text(locationTrustOn
                         ? "Showing \(firstName) your gym — On"
                         : "Show \(firstName) your gym when you train")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Capsule().fill(GQColors.surfaceBase))
                .overlay(Capsule().stroke(GQColors.borderDefault, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .id(locationTrustTick)

            // Reaction streak — visible only when ≥5 of last 6 of THEIR
            // workouts received a reaction from me.
            if reactionStreakHit {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(GQGradients.primary)
                    Text("Reaction streak — \(reactionsToThemRecent)/6")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(GQColors.surfaceBase))
                .overlay(Capsule().stroke(GQColors.borderDefault, lineWidth: 0.5))
            }

            // Quick replies — three structured replies the user can fire.
            QuickReplyButtons(toUserId: userId, fromUserId: currentProfile.id)

            // Auto-react 🔥 toggle.
            Button {
                AutoReactStore.toggle(userId)
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                autoReactTick &+= 1
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: autoReactOn ? "checkmark.circle.fill" : "flame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(autoReactOn ? AnyShapeStyle(AlivePresence.green) : AnyShapeStyle(GQGradients.primary))
                    Text(autoReactOn
                         ? "Auto 🔥 when \(firstName) starts — On"
                         : "Send 🔥 automatically when \(firstName) starts")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Capsule().fill(GQColors.surfaceBase))
                .overlay(Capsule().stroke(GQColors.borderDefault, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .id(autoReactTick) // recompute autoReactOn after toggle
        }
        .padding(.horizontal, 16)
    }

    private var firstName: String {
        (userProfile?.name ?? "them").split(separator: " ").first.map(String.init) ?? (userProfile?.name ?? "them")
    }

    private var autoReactOn: Bool {
        _ = autoReactTick
        return AutoReactStore.contains(userId)
    }

    private var locationTrustOn: Bool {
        _ = locationTrustTick
        return LocationTrustedFriendsStore.contains(userId)
    }

    /// Distinct workout sessions of the target user that received a reaction
    /// from the current user in the last 30 days. Approximated via the
    /// `sessionStartedAt` field on LiveReaction (no cross-user Workout
    /// records exist locally — the device only holds the current user's
    /// own Workout history).
    private var reactionsToThemRecent: Int {
        let myId = currentProfile.id
        let cutoff = Date().addingTimeInterval(-30 * 86_400)
        let mineToThem = profileSheetReactions
            .filter { $0.fromUserId == myId && $0.toUserId == userId && $0.sessionStartedAt >= cutoff }
        // Bucket by sessionStartedAt rounded to the hour so multiple
        // reactions to the same session don't double-count.
        let buckets = Set(mineToThem.map { Int($0.sessionStartedAt.timeIntervalSince1970 / 3600) })
        return min(6, buckets.count)
    }

    /// Streak fires when ≥5 of the last 6 sessions received a reaction.
    private var reactionStreakHit: Bool { reactionsToThemRecent >= 5 }

    // MARK: - Follow Logic

    private func loadFollowState() {
        let myId = currentProfile.id
        let targetId = userId
        let descriptor = FetchDescriptor<Friend>(predicate: #Predicate {
            $0.userId == myId && $0.odId == targetId
        })
        isFollowing = ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    private func toggleFollow() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        let targetId = userId
        let myId = currentProfile.id

        if isFollowing {
            isFollowing = false
            currentProfile.followingCount = max(0, currentProfile.followingCount - 1)
            let descriptor = FetchDescriptor<Friend>(predicate: #Predicate {
                $0.userId == myId && $0.odId == targetId
            })
            if let records = try? modelContext.fetch(descriptor) {
                for record in records { modelContext.delete(record) }
            }

            // Sync unfollow to Supabase
            if FeatureFlags.shared.supabaseSyncEnabled {
                Task {
                    do {
                        try await SupabaseConfig.client.from("follows")
                            .delete()
                            .eq("follower_id", value: myId.uuidString)
                            .eq("following_id", value: targetId.uuidString)
                            .execute()
                    } catch {
                        print("[UserProfileSheet] Supabase unfollow sync failed: \(error)")
                    }
                }
            }
        } else {
            isFollowing = true
            // Soft prompt: ask whether to also share gym location with
            // this friend. Skip if already in the trust list.
            if !LocationTrustedFriendsStore.contains(targetId) {
                showLocationTrustPrompt = true
            }
            currentProfile.followingCount += 1
            let name = userProfile?.name ?? ""
            let username = userProfile?.username ?? ""
            let friend = Friend(userId: myId, odId: targetId, odName: name, odUsername: username)
            modelContext.insert(friend)

            // Sync follow to Supabase
            if FeatureFlags.shared.supabaseSyncEnabled {
                Task {
                    do {
                        let dto = FollowDTO(followerId: myId, followingId: targetId)
                        try await SupabaseSyncService.shared.insert(dto, table: "follows")
                    } catch {
                        print("[UserProfileSheet] Supabase follow sync failed: \(error)")
                    }
                }
            }
        }

        // Update target's follower count
        if let target = userProfile {
            target.followerCount += isFollowing ? 1 : -1
        }
        try? modelContext.save()
    }
}
