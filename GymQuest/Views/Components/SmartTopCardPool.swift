// Home Slot 1 — Smart Top Card with 12-candidate priority pool.
// Design v4.3 §4A. Re-evaluates on every open.

import SwiftUI

enum SmartTopCardKind: Int, CaseIterable {
    case resumeActiveWorkout = 1
    case startAtSavedGym
    case followedAtMyGym
    case friendPostedRecently
    case friendsTrainingNow
    case crewEventSoon
    case todaysPlannedWorkout
    case unreadReactions
    case friendJustFinished
    case mutualHitPR
    case streakDanger
    case squadChallengeNearComplete

    var headline: String {
        switch self {
        case .resumeActiveWorkout: return "resume your workout"
        case .startAtSavedGym: return "you're at your gym — start"
        case .followedAtMyGym: return "someone you follow is at your gym"
        case .friendPostedRecently: return "a friend just posted"
        case .friendsTrainingNow: return "your friends are training"
        case .crewEventSoon: return "crew event soon"
        case .todaysPlannedWorkout: return "today's plan"
        case .unreadReactions: return "people reacted to your last session"
        case .friendJustFinished: return "a friend just finished"
        case .mutualHitPR: return "a mutual hit a PR 🐐"
        case .streakDanger: return "your streak is on the line"
        case .squadChallengeNearComplete: return "your squad's almost there"
        }
    }

    var icon: String {
        switch self {
        case .resumeActiveWorkout: return "play.fill"
        case .startAtSavedGym: return "mappin.circle.fill"
        case .followedAtMyGym: return "person.crop.circle.fill"
        case .friendPostedRecently: return "bell.badge.fill"
        case .friendsTrainingNow: return "flame.fill"
        case .crewEventSoon: return "calendar.badge.clock"
        case .todaysPlannedWorkout: return "list.bullet.clipboard.fill"
        case .unreadReactions: return "heart.fill"
        case .friendJustFinished: return "checkmark.circle.fill"
        case .mutualHitPR: return "trophy.fill"
        case .streakDanger: return "exclamationmark.triangle.fill"
        case .squadChallengeNearComplete: return "person.3.sequence.fill"
        }
    }

    var ctaLabel: String {
        switch self {
        case .resumeActiveWorkout: return "resume"
        case .startAtSavedGym: return "start"
        case .followedAtMyGym: return "join"
        case .friendPostedRecently: return "view"
        case .friendsTrainingNow: return "see who"
        case .crewEventSoon: return "RSVP"
        case .todaysPlannedWorkout: return "start"
        case .unreadReactions: return "open"
        case .friendJustFinished: return "react"
        case .mutualHitPR: return "react"
        case .streakDanger: return "save it"
        case .squadChallengeNearComplete: return "lift now"
        }
    }
}

struct SmartTopCardSignals {
    var hasActiveWorkout: Bool = false
    var atSavedGym: Bool = false
    var followedAtSameGymCount: Int = 0
    var friendPostInLast20m: Bool = false
    var friendsTrainingNow: Int = 0
    var crewEventInNext6h: Bool = false
    var crewEventFriendsCount: Int = 0
    var hasTodaysPlannedWorkout: Bool = false
    var unreadReactionsCount: Int = 0
    var friendJustFinishedWithin10m: Bool = false
    var mutualHitPRWithin30m: Bool = false
    var streakDanger: Bool = false
    var squadChallengeProgress: Double = 0  // 0...1
}

enum SmartTopCardPicker {
    /// Picks the highest-priority candidate. Order matches design §4A.
    static func pick(_ s: SmartTopCardSignals) -> SmartTopCardKind? {
        if s.hasActiveWorkout { return .resumeActiveWorkout }
        if s.atSavedGym { return .startAtSavedGym }
        if s.followedAtSameGymCount > 0 { return .followedAtMyGym }
        if s.friendPostInLast20m { return .friendPostedRecently }
        if s.friendsTrainingNow >= 2 { return .friendsTrainingNow }
        if s.crewEventInNext6h && s.crewEventFriendsCount >= 2 { return .crewEventSoon }
        if s.hasTodaysPlannedWorkout { return .todaysPlannedWorkout }
        if s.unreadReactionsCount >= 3 { return .unreadReactions }
        if s.friendJustFinishedWithin10m { return .friendJustFinished }
        if s.mutualHitPRWithin30m { return .mutualHitPR }
        if s.streakDanger { return .streakDanger }
        if s.squadChallengeProgress >= 0.7 { return .squadChallengeNearComplete }
        return nil
    }
}

struct SmartTopCardView: View {
    let kind: SmartTopCardKind
    let detailLine: String?
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: kind.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(LinearGradient(colors: [.purple, .blue],
                                                              startPoint: .topLeading,
                                                              endPoint: .bottomTrailing)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.headline)
                        .font(.system(size: 16, weight: .semibold))
                    if let d = detailLine {
                        Text(d)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Text(kind.ctaLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.white.opacity(0.10)))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
