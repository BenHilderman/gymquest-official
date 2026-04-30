// AccountRiskState — content-safety phase 4E.
//
// Cached risk score + tier per user. BotHeuristicService writes here
// whenever it (re)evaluates. RateLimitService reads `tier` to pick the
// right cap. Server canonical state is in `account_risk_score` table
// (Phase 4F migration); this row mirrors locally for fast reads.

import Foundation
import SwiftData

@Model
final class AccountRiskState {
    @Attribute(.unique) var userId: UUID
    var score: Int
    var tierRaw: String
    /// Comma-joined list of recent risk signals — debug aid only.
    var recentSignals: String
    var lastEvaluatedAt: Date

    init(
        userId: UUID,
        score: Int = 0,
        tier: AbuseThresholds.AccountTier = .standard,
        recentSignals: String = "",
        lastEvaluatedAt: Date = Date()
    ) {
        self.userId = userId
        self.score = score
        self.tierRaw = tier.rawValue
        self.recentSignals = recentSignals
        self.lastEvaluatedAt = lastEvaluatedAt
    }

    var tier: AbuseThresholds.AccountTier {
        get { AbuseThresholds.AccountTier(rawValue: tierRaw) ?? .standard }
        set { tierRaw = newValue.rawValue }
    }
}
