import Foundation
import SwiftData

/// Lightweight "what are you doing right now" signal. One record per user;
/// updated when they start/stop a workout. Drives the LiveNowStrip, the
/// presence ring on every avatar in the app, and the ambient header strip.
///
/// Six discrete states map onto three ring colors per the Alive spec:
/// idle / ghost = no ring · arriving = gold · training/resting/finishedRecently = green.
enum PresenceStatus: String, Codable, CaseIterable {
    case idle              // not training
    case arriving          // geofence detected, no workout started yet
    case training          // actively in a workout
    case resting           // between sets
    case finishedRecently  // within 10 min of last set
    case ghost             // user opted out of presence for this session
}

@Model
final class UserPresenceState {
    @Attribute(.unique) var userId: UUID
    var statusRaw: String
    var workoutTypeRaw: String?
    var startedAt: Date?
    /// Set when the user finishes; surfaces in `finishedRecently` window
    /// and triggers auto-cleanup of `gymId` / `gymName` per the privacy rule.
    var endedAt: Date?
    /// Friend-only location detail. Strangers never read this — they see
    /// only the binary active signal. Null when the user picked "Just-active"
    /// or "Ghost" at session start.
    var gymId: UUID?
    var gymName: String?
    /// Per-session opt-ins (e.g. "ghost", "auto-react-eligible"). Cleared
    /// at session end alongside gymId.
    var sessionTags: [String]
    var updatedAt: Date

    init(
        userId: UUID,
        status: PresenceStatus = .idle,
        workoutType: String? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        gymId: UUID? = nil,
        gymName: String? = nil,
        sessionTags: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.userId = userId
        self.statusRaw = status.rawValue
        self.workoutTypeRaw = workoutType
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.gymId = gymId
        self.gymName = gymName
        self.sessionTags = sessionTags
        self.updatedAt = updatedAt
    }

    var status: PresenceStatus {
        get { PresenceStatus(rawValue: statusRaw) ?? .idle }
        set { statusRaw = newValue.rawValue }
    }

    /// True when the user is mid-workout (training or resting between sets).
    var isActive: Bool {
        status == .training || status == .resting
    }

    /// True when the user shows a ring of any color. Ghost + idle have no ring.
    var showsRing: Bool {
        switch status {
        case .arriving, .training, .resting, .finishedRecently: return true
        case .idle, .ghost: return false
        }
    }

    /// Minutes elapsed since the current workout started. Rendered as
    /// "22 min in" under a live avatar.
    var minutesIn: Int {
        guard isActive, let start = startedAt else { return 0 }
        return max(0, Int(Date().timeIntervalSince(start) / 60))
    }
}
