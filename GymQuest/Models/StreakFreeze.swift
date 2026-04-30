// StreakFreeze — content-psychology pass.
//
// Trusted-tier accounts get one auto-applied freeze per calendar month.
// When the user misses a day, the streak persists *if* a freeze is
// available — freeze gets consumed silently, no panic UI, no shame.
//
// Why we have it:
//   - Loss-aversion is a real motivator but life happens. Hard streaks
//     punish vacations, sickness, family stuff — drives uninstall.
//   - Trust tier means we know this isn't a freeloader (>30d, >10
//     workouts, no moderation strikes per AbuseThresholds.baseTier).
//   - One per month is generous enough to forgive real life, scarce
//     enough that it still feels meaningful.

import Foundation
import SwiftData

@Model
final class StreakFreeze {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    /// ISO month key, e.g. "2026-04". One freeze per month per user.
    var monthKey: String
    /// When the freeze was granted to the account. Auto-applied on
    /// the first day of the month for eligible (trusted) tiers.
    var grantedAt: Date
    /// When the freeze was consumed (the day it saved a streak).
    /// Nil while still available.
    var consumedAt: Date?

    init(userId: UUID, monthKey: String, grantedAt: Date = Date()) {
        self.id = UUID()
        self.userId = userId
        self.monthKey = monthKey
        self.grantedAt = grantedAt
    }

    var isAvailable: Bool { consumedAt == nil }

    /// ISO "YYYY-MM" key for a given date.
    static func monthKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }
}
