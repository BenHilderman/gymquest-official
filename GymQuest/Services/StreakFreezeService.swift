// StreakFreezeService — content-psychology pass.
//
// Trusted-tier accounts get one auto-granted freeze per calendar month.
// When the streak engine detects a missed day, this service is consulted
// before the streak gets broken — if a freeze is available, consume it
// silently and the streak persists.
//
// Reads tier from BotHeuristicService.cachedTier so probationary /
// throttled / paused accounts don't get the perk.

import Foundation
import SwiftData

@MainActor
enum StreakFreezeService {

    /// Idempotently grant the user this month's freeze if they're
    /// trusted-tier and don't already have one for this month.
    /// Call from app-launch / on tier change.
    @discardableResult
    static func grantIfEligible(
        userId: UUID,
        in context: ModelContext,
        now: Date = Date()
    ) -> StreakFreeze? {
        let tier = BotHeuristicService.cachedTier(for: userId, in: context)
        guard tier == .trusted else { return nil }

        let monthKey = StreakFreeze.monthKey(for: now)
        let descriptor = FetchDescriptor<StreakFreeze>(
            predicate: #Predicate { $0.userId == userId && $0.monthKey == monthKey }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }

        let freeze = StreakFreeze(userId: userId, monthKey: monthKey, grantedAt: now)
        context.insert(freeze)
        try? context.save()
        return freeze
    }

    /// Returns true if the caller has an available freeze for the
    /// month containing `forDay`. Use as a check before breaking the
    /// streak in the streak engine.
    static func hasAvailableFreeze(
        userId: UUID,
        forDay: Date,
        in context: ModelContext
    ) -> Bool {
        availableFreeze(userId: userId, forDay: forDay, in: context) != nil
    }

    /// Consumes the freeze for the month containing `forDay`. Marks
    /// `consumedAt = forDay`. Idempotent — calling twice is a no-op.
    @discardableResult
    static func consumeFreeze(
        userId: UUID,
        forDay: Date,
        in context: ModelContext
    ) -> Bool {
        guard let freeze = availableFreeze(userId: userId, forDay: forDay, in: context) else {
            return false
        }
        freeze.consumedAt = forDay
        try? context.save()
        return true
    }

    /// Counts of (granted this year, consumed this year). For the
    /// Profile settings detail row.
    static func usage(
        userId: UUID,
        in context: ModelContext,
        now: Date = Date()
    ) -> (granted: Int, consumed: Int) {
        let cal = Calendar(identifier: .gregorian)
        let yearStart = cal.date(from: cal.dateComponents([.year], from: now)) ?? .distantPast
        let descriptor = FetchDescriptor<StreakFreeze>(
            predicate: #Predicate { $0.userId == userId && $0.grantedAt >= yearStart }
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return (rows.count, rows.filter { $0.consumedAt != nil }.count)
    }

    // MARK: - Private

    private static func availableFreeze(
        userId: UUID,
        forDay: Date,
        in context: ModelContext
    ) -> StreakFreeze? {
        let monthKey = StreakFreeze.monthKey(for: forDay)
        let descriptor = FetchDescriptor<StreakFreeze>(
            predicate: #Predicate { row in
                row.userId == userId
                    && row.monthKey == monthKey
                    && row.consumedAt == nil
            }
        )
        return (try? context.fetch(descriptor))?.first
    }
}
