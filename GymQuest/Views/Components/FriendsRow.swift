import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Single merged crew member for the unified row.
struct FriendsMember: Identifiable {
    let id: UUID
    let name: String
    let username: String
    let avatarData: Data?
    let status: Status
    let statusText: String       // "Push · 6 min" or "yesterday" or "2d ago"

    enum Status {
        case live(workoutType: String?)  // green ring, currently training
        case recent                       // purple ring, posted recently
        case inactive                     // gray, >3 days no activity
    }
}

/// Pure builder that turns raw queries (follows, posts, presence, profiles)
/// into a sorted FriendsMember list. Lifted out of ExploreView so the
/// Friends tab can render the same strip without duplicating 60 lines.
enum FriendsMemberBuilder {
    static func build(
        selfId: UUID,
        follows: [Friend],
        allPosts: [Post],
        liveNowStates: [UserPresenceState],
        profilesById: [UUID: UserProfile]
    ) -> [FriendsMember] {
        let followedIds = Set(follows.filter { $0.userId == selfId }.map(\.odId))
        guard !followedIds.isEmpty else { return [] }

        let liveIds = Set(liveNowStates.map(\.userId))
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let inactiveThreshold = Date().addingTimeInterval(-3 * 86_400)

        var latestPost: [UUID: Post] = [:]
        for post in allPosts where followedIds.contains(post.authorId) {
            if let existing = latestPost[post.authorId], existing.timestamp >= post.timestamp { continue }
            latestPost[post.authorId] = post
        }

        let members: [FriendsMember] = followedIds.compactMap { friendId in
            let profile = profilesById[friendId]
            let follow = follows.first(where: { $0.odId == friendId })
            let name = profile?.name ?? follow?.odName ?? "Friend"
            let username = profile?.username ?? follow?.odUsername ?? ""
            let avatarData = profile?.profilePhotoData

            if liveIds.contains(friendId) {
                let state = liveNowStates.first(where: { $0.userId == friendId })
                let type = state?.workoutTypeRaw?.capitalized ?? "Training"
                let mins = state?.minutesIn ?? 0
                return FriendsMember(
                    id: friendId, name: name, username: username, avatarData: avatarData,
                    status: .live(workoutType: state?.workoutTypeRaw),
                    statusText: "\(type) · \(mins)m"
                )
            }

            if let post = latestPost[friendId], post.timestamp >= weekAgo {
                let type = post.workoutType?.capitalized ?? "Workout"
                let ago = RelativeDateString.compact(from: post.timestamp)
                return FriendsMember(
                    id: friendId, name: name, username: username, avatarData: avatarData,
                    status: .recent,
                    statusText: "\(type) · \(ago)"
                )
            }

            let lastDate = latestPost[friendId]?.timestamp
            if lastDate == nil || lastDate! < inactiveThreshold {
                let ago = lastDate.map { RelativeDateString.compact(from: $0) } ?? "—"
                let type = latestPost[friendId]?.workoutType?.capitalized
                let text: String = type.map { "\($0) · \(ago)" } ?? ago
                return FriendsMember(
                    id: friendId, name: name, username: username, avatarData: avatarData,
                    status: .inactive,
                    statusText: text
                )
            }

            return nil
        }

        return members.sorted { lhs, rhs in
            priority(lhs.status) < priority(rhs.status)
        }
    }

    private static func priority(_ status: FriendsMember.Status) -> Int {
        switch status {
        case .live: return 0
        case .recent: return 1
        case .inactive: return 2
        }
    }
}

/// One horizontal row replacing both LiveNowStrip and FriendFeedSection.
/// Green ring = training now, purple = posted recently, gray = inactive.
/// ~70pt tall. Tap avatar → callback. [+] at the end starts a workout.
struct FriendsRow: View {
    let members: [FriendsMember]
    let onTapMember: (FriendsMember) -> Void
    let onStartWorkout: () -> Void

    @State private var pulse: Bool = false

    var body: some View {
        if members.isEmpty { EmptyView() } else {
            VStack(alignment: .leading, spacing: 6) {
                // "ACTIVE NOW · N friends today" — compact header with
                // a green presence dot, matches the cleaner shipped
                // design instead of a loud "FRIENDS" label.
                HStack(spacing: 6) {
                    Circle()
                        .fill(GQColors.success)
                        .frame(width: 6, height: 6)
                    Text("ACTIVE NOW")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundColor(GQColors.textTertiary)
                    Text("·")
                        .foregroundColor(GQColors.textTertiary)
                    Text(activeLabel)
                        .font(.system(size: 10))
                        .foregroundColor(GQColors.textTertiary)
                }
                .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(members) { member in
                            memberCell(member)
                        }
                        startCell
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
            .onAppear { pulse = true }
        }
    }

    /// Small status string in the header — "N active today" reads as
    /// presence rather than a static count.
    private var activeLabel: String {
        let liveCount = members.filter { isLive($0) }.count
        if liveCount > 0 {
            return "\(liveCount) training now"
        }
        return "\(members.count) friends"
    }

    private func memberCell(_ member: FriendsMember) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            onTapMember(member)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    // Thin green ring only on live members. Recent/inactive get
                    // no ring — just the avatar. Keeps the row clean and
                    // reserves accent color for the single "training now"
                    // signal, Apple-style.
                    if isLive(member) {
                        Circle()
                            .stroke(GQColors.success, lineWidth: 2)
                            .frame(width: 48, height: 48)
                            .scaleEffect(pulse ? 1.04 : 1.0)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                    }

                    avatarImage(member)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .opacity(isInactive(member) ? 0.55 : 1.0)

                    if isLive(member) {
                        Circle()
                            .fill(GQColors.success)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(GQColors.background, lineWidth: 2))
                            .frame(width: 48, height: 48, alignment: .bottomTrailing)
                    }
                }

                Text(firstName(member))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: 56)

                // Tiny workout-type glyph for live members — no text,
                // just the icon in textTertiary so it reads as a quiet
                // hint ("she's doing pull"). Stays out of the way when
                // there's no current workout.
                if let icon = workoutIcon(for: member) {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(GQColors.textTertiary)
                        .frame(height: 10)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// SF symbol matching the member's current workout type, when live.
    private func workoutIcon(for member: FriendsMember) -> String? {
        guard case let .live(workoutType) = member.status, let raw = workoutType else { return nil }
        switch raw.lowercased() {
        case "push": return "figure.strengthtraining.traditional"
        case "pull": return "figure.rower"
        case "legs": return "figure.squat"
        case "cardio", "run", "running": return "figure.run"
        case "upper body", "upper": return "figure.arms.open"
        case "lower body", "lower": return "figure.cross.training"
        case "full body": return "figure.cross.training"
        case "yoga": return "figure.yoga"
        case "hiit": return "figure.highintensity.intervaltraining"
        case "glutes": return "figure.stair.stepper"
        case "abs": return "figure.core.training"
        default: return "dumbbell.fill"
        }
    }

    private var startCell: some View {
        Button(action: onStartWorkout) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(GQColors.borderDefault, lineWidth: 1.5)
                        .frame(width: 48, height: 48)
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GQGradients.primary)
                }
                Text("Start")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(GQColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func avatarImage(_ member: FriendsMember) -> some View {
        #if canImport(UIKit)
        if let data = member.avatarData, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Circle().fill(isInactive(member) ? AnyShapeStyle(GQColors.surfaceSecondary) : AnyShapeStyle(GQGradients.primary))
                Text(String(member.name.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        #else
        Circle().fill(GQColors.surfaceSecondary)
        #endif
    }

    private func isLive(_ member: FriendsMember) -> Bool {
        if case .live = member.status { return true }
        return false
    }

    private func isInactive(_ member: FriendsMember) -> Bool {
        if case .inactive = member.status { return true }
        return false
    }

    private func firstName(_ member: FriendsMember) -> String {
        member.name.split(separator: " ").first.map(String.init) ?? member.name
    }
}
