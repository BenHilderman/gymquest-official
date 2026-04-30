// RateLimitWindow — content-safety phase 4A.
//
// One row per (action, userId, window) pair. Rolling-window counters
// capped at 1h or 24h. Garbage-collected by RateLimitService.gcExpired
// on launch + periodically.

import Foundation
import SwiftData

@Model
final class RateLimitWindow {
    @Attribute(.unique) var id: UUID
    /// AbuseThresholds.Action.rawValue for the rate-limited action.
    var actionKey: String
    /// User the limit applies to.
    var userId: UUID
    /// Per-target key (e.g. recipient userId for `dmSendToSingleRecipient`).
    /// Nil for non-targeted actions.
    var targetKey: String?
    /// Rolling-window length. "hour" or "day".
    var windowKindRaw: String
    /// When the window started counting. `count` is the number of
    /// actions in [windowStartedAt, windowStartedAt + window].
    var windowStartedAt: Date
    var count: Int

    enum WindowKind: String {
        case hour
        case day

        var seconds: TimeInterval {
            switch self {
            case .hour: return 3600
            case .day: return 86_400
            }
        }
    }

    var windowKind: WindowKind {
        get { WindowKind(rawValue: windowKindRaw) ?? .hour }
        set { windowKindRaw = newValue.rawValue }
    }

    init(
        actionKey: String,
        userId: UUID,
        targetKey: String? = nil,
        windowKind: WindowKind = .hour,
        windowStartedAt: Date = Date(),
        count: Int = 0
    ) {
        self.id = UUID()
        self.actionKey = actionKey
        self.userId = userId
        self.targetKey = targetKey
        self.windowKindRaw = windowKind.rawValue
        self.windowStartedAt = windowStartedAt
        self.count = count
    }

    /// True when the window has already rolled past its end. Caller
    /// should discard or reset.
    func isExpired(asOf now: Date = Date()) -> Bool {
        now.timeIntervalSince(windowStartedAt) >= windowKind.seconds
    }

    var windowEndsAt: Date {
        windowStartedAt.addingTimeInterval(windowKind.seconds)
    }
}
