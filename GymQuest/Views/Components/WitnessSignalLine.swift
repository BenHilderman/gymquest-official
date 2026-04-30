// WitnessSignalLine — content-psychology pass.
//
// Slim line on the post-save success surface that names specific people
// who are about to see the post. Closes a different psychological loop
// than the personal one — "your post will be seen" is social proof of
// effort, not just self-recognition.
//
// Resolved from real data only:
//   • followers currently `.training` (will see it on their feed soon)
//   • followers at the user's saved gym right now
// Hides entirely when no signal — no fake engagement bait.

import SwiftUI
import SwiftData

struct WitnessSignalLine: View {
    let signalText: String?

    var body: some View {
        if let text = signalText {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(GQColors.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(GQColors.overlayLight)
            )
        }
    }
}

@MainActor
enum WitnessSignal {
    /// Resolves the witness line for the current user. Returns nil
    /// when nobody specific is about to see the post — we never fake it.
    static func line(
        currentUserId: UUID,
        savedGymNames: Set<String>,
        in context: ModelContext
    ) -> String? {
        // Pull live presence + my follow graph.
        let followsDescriptor = FetchDescriptor<Friend>(
            predicate: #Predicate { $0.userId == currentUserId }
        )
        let myFollows = (try? context.fetch(followsDescriptor)) ?? []
        let followedIds = Set(myFollows.map(\.odId))
        guard !followedIds.isEmpty else { return nil }

        let now = Date()
        let activeCutoff = now.addingTimeInterval(-3 * 3600)
        let presenceDescriptor = FetchDescriptor<UserPresenceState>()
        let allPresence = (try? context.fetch(presenceDescriptor)) ?? []

        // Friends currently training.
        let liveFriends = allPresence.filter { state in
            followedIds.contains(state.userId)
                && state.status == .training
                && (state.startedAt ?? .distantPast) >= activeCutoff
        }

        // Friends present at one of my saved gyms (regardless of status).
        let friendsAtMyGym = allPresence.filter { state in
            followedIds.contains(state.userId)
                && state.gymName.map(savedGymNames.contains) == true
        }

        // Pull names — use first matching profile.
        let userProfileDescriptor = FetchDescriptor<UserProfile>()
        let allProfiles = (try? context.fetch(userProfileDescriptor)) ?? []
        let nameLookup = Dictionary(uniqueKeysWithValues: allProfiles.map { ($0.id, $0.name) })

        // Prioritize "at your gym" — it's the more specific, surprising line.
        if let atGym = friendsAtMyGym.first,
           let name = nameLookup[atGym.userId]?.lowercased(),
           let gym = atGym.gymName?.lowercased() {
            return "\(name) is at \(gym) right now"
        }
        if liveFriends.count >= 2 {
            return "\(liveFriends.count) friends are training — they'll see this"
        }
        if let live = liveFriends.first,
           let name = nameLookup[live.userId]?.lowercased() {
            return "\(name) is about to see this"
        }
        return nil
    }
}
