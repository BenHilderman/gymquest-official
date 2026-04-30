// RateLimitService — content-safety phase 4A.
//
// Local-first rate limiter. Every create call (post, comment, DM, story,
// follow, etc.) routes through `RateLimitService.allow(...)` before the
// action lands. A `Decision` is the single contract:
//
//   .allowed                   — proceed normally
//   .softLimited(retryAfter)   — show toast, queue or drop the action
//   .hardCapped(retryAfter)    — show full sheet, block until window opens
//
// Tier-aware: higher trust → higher caps. Tier read from the cached
// `AccountRiskState` (Phase 4E).
//
// Server canonical mirror (Phase 4F) writes the same counters server-side
// so a malicious client can't lie about counts. Local-first means soft
// rate-limit feels instant; server reconciliation runs out-of-band.

import Foundation
import SwiftData

@MainActor
enum RateLimitService {

    enum Decision: Equatable {
        case allowed
        case softLimited(retryAfter: TimeInterval)
        case hardCapped(retryAfter: TimeInterval)

        var isBlocking: Bool {
            switch self {
            case .allowed: return false
            case .softLimited, .hardCapped: return true
            }
        }
    }

    /// Check + record an action against the user's rate-limit windows.
    /// Returns `.allowed` and increments the counter atomically when
    /// under cap. Returns the limit decision when over.
    @discardableResult
    static func allow(
        _ action: AbuseThresholds.Action,
        by userId: UUID,
        targetKey: String? = nil,
        tier: AbuseThresholds.AccountTier = .standard,
        in context: ModelContext
    ) -> Decision {
        let now = Date()

        // Hourly window check.
        if let hourly = AbuseThresholds.hourlyLimit(action, tier: tier) {
            let window = fetchOrCreate(
                actionKey: action.rawValue,
                userId: userId,
                targetKey: targetKey,
                kind: .hour,
                in: context
            )
            // Roll the window forward if expired.
            if window.isExpired(asOf: now) {
                window.windowStartedAt = now
                window.count = 0
            }
            if window.count >= hourly {
                let retry = max(0, window.windowEndsAt.timeIntervalSince(now))
                return .softLimited(retryAfter: retry)
            }
            window.count += 1
        }

        // Daily window check (only some actions have a daily cap).
        if let daily = AbuseThresholds.dailyLimit(action, tier: tier) {
            let window = fetchOrCreate(
                actionKey: action.rawValue,
                userId: userId,
                targetKey: nil,        // daily caps are user-wide, not per-target
                kind: .day,
                in: context
            )
            if window.isExpired(asOf: now) {
                window.windowStartedAt = now
                window.count = 0
            }
            if window.count >= daily {
                let retry = max(0, window.windowEndsAt.timeIntervalSince(now))
                return .hardCapped(retryAfter: retry)
            }
            window.count += 1
        }

        try? context.save()
        return .allowed
    }

    /// Read-only "could this action go through right now?" check —
    /// doesn't increment. Useful for grey-out states in the UI.
    static func wouldAllow(
        _ action: AbuseThresholds.Action,
        by userId: UUID,
        targetKey: String? = nil,
        tier: AbuseThresholds.AccountTier = .standard,
        in context: ModelContext
    ) -> Decision {
        let now = Date()
        if let hourly = AbuseThresholds.hourlyLimit(action, tier: tier),
           let window = fetch(actionKey: action.rawValue, userId: userId, targetKey: targetKey, kind: .hour, in: context),
           !window.isExpired(asOf: now),
           window.count >= hourly {
            return .softLimited(retryAfter: max(0, window.windowEndsAt.timeIntervalSince(now)))
        }
        if let daily = AbuseThresholds.dailyLimit(action, tier: tier),
           let window = fetch(actionKey: action.rawValue, userId: userId, targetKey: nil, kind: .day, in: context),
           !window.isExpired(asOf: now),
           window.count >= daily {
            return .hardCapped(retryAfter: max(0, window.windowEndsAt.timeIntervalSince(now)))
        }
        return .allowed
    }

    /// Garbage collect expired windows. Called at app launch + opportunistically
    /// from any allow() invocation that finds a stale row.
    static func gcExpired(in context: ModelContext) {
        let now = Date()
        let descriptor = FetchDescriptor<RateLimitWindow>()
        guard let rows = try? context.fetch(descriptor) else { return }
        for row in rows where row.isExpired(asOf: now.addingTimeInterval(-86_400)) {
            // Older than 24h past expiry → drop entirely.
            context.delete(row)
        }
        try? context.save()
    }

    // MARK: - Private

    private static func fetch(
        actionKey: String,
        userId: UUID,
        targetKey: String?,
        kind: RateLimitWindow.WindowKind,
        in context: ModelContext
    ) -> RateLimitWindow? {
        let kindRaw = kind.rawValue
        let descriptor = FetchDescriptor<RateLimitWindow>(
            predicate: #Predicate { row in
                row.actionKey == actionKey
                    && row.userId == userId
                    && row.targetKey == targetKey
                    && row.windowKindRaw == kindRaw
            }
        )
        return (try? context.fetch(descriptor))?.first
    }

    private static func fetchOrCreate(
        actionKey: String,
        userId: UUID,
        targetKey: String?,
        kind: RateLimitWindow.WindowKind,
        in context: ModelContext
    ) -> RateLimitWindow {
        if let existing = fetch(actionKey: actionKey, userId: userId, targetKey: targetKey, kind: kind, in: context) {
            return existing
        }
        let row = RateLimitWindow(
            actionKey: actionKey,
            userId: userId,
            targetKey: targetKey,
            windowKind: kind
        )
        context.insert(row)
        return row
    }
}
