// BotHeuristicService — content-safety phase 4E.
//
// Rolls up risk signals into a single score per user and assigns a tier.
// Local-first; the server canonical pipeline (Phase 4G Edge Function)
// runs the same heuristics on the server side and reconciles via the
// `account_risk_score` table.
//
// Design contract: scoring is deterministic and signal-additive — the
// same inputs always produce the same score. Tier is purely a function
// of score (see AbuseThresholds.tier(forRiskScore:)).
//
// Caller pattern: invoke `evaluate(for:)` whenever new content lands
// (post create, comment create, signup, etc.). Cheap enough to run
// inline; reads the user's recent activity from SwiftData.

import Foundation
import SwiftData

@MainActor
enum BotHeuristicService {

    /// Evaluate (or refresh) the risk state for a user. Writes
    /// `AccountRiskState` and returns the resolved tier.
    @discardableResult
    static func evaluate(
        for userId: UUID,
        accountAgeSeconds: TimeInterval,
        workoutCount: Int,
        in context: ModelContext
    ) -> AbuseThresholds.AccountTier {
        var score = 0
        var triggeredSignals: [AbuseThresholds.RiskSignal] = []

        // Tenure baseline — a brand-new account with high activity is
        // suspicious. Pull recent counters to test.
        if accountAgeSeconds < 86_400 {
            let recentActions = recentActionCount(userId: userId, sinceMinutes: 60, in: context)
            if recentActions > 10 {
                score += AbuseThresholds.points(for: .youngAccountHighActivity)
                triggeredSignals.append(.youngAccountHighActivity)
            }
        }

        // Zero-workouts + high social activity = bot signature.
        if accountAgeSeconds >= 7 * 86_400 && workoutCount == 0 {
            let socialActions = recentActionCount(userId: userId, sinceMinutes: 24 * 60, in: context)
            if socialActions > 50 {
                score += AbuseThresholds.points(for: .zeroWorkoutsHighSocial)
                triggeredSignals.append(.zeroWorkoutsHighSocial)
            }
        }

        // Repeated content text — same caption posted 3+ times in 24h.
        if hasRepeatedContent(userId: userId, in: context) {
            score += AbuseThresholds.points(for: .repeatedContentText)
            triggeredSignals.append(.repeatedContentText)
        }

        // User reports spike — ≥ 5 reports against this user in 24h.
        let reportsAgainst = recentReportsAgainst(userId: userId, in: context)
        if reportsAgainst >= 5 {
            score += AbuseThresholds.points(for: .userReportsSpike)
            triggeredSignals.append(.userReportsSpike)
        }

        // Mention flood — ≥ 10 mentions in single post, repeated 3+ times.
        if hasMentionFlood(userId: userId, in: context) {
            score += AbuseThresholds.points(for: .mentionFlood)
            triggeredSignals.append(.mentionFlood)
        }

        // Identical voice-note durations — bots often re-upload the
        // same prerecorded TTS clip.
        if hasIdenticalVoiceNoteDurations(userId: userId, in: context) {
            score += AbuseThresholds.points(for: .identicalVoiceNoteDurations)
            triggeredSignals.append(.identicalVoiceNoteDurations)
        }

        // Resolve tier. If score-based tier is more permissive than the
        // base tier (probationary etc.), use the base — risk only ever
        // restricts further, never relaxes the natural tenure floor.
        let scoreBasedTier = AbuseThresholds.tier(forRiskScore: score)
        let baseTier = AbuseThresholds.baseTier(
            accountAgeSeconds: accountAgeSeconds,
            workoutCount: workoutCount,
            moderationStrikesLast90Days: reportsAgainst
        )
        let finalTier = restrict(baseTier, by: scoreBasedTier)

        upsertState(
            userId: userId,
            score: score,
            tier: finalTier,
            signals: triggeredSignals,
            in: context
        )
        return finalTier
    }

    /// Read the cached tier without re-evaluating. Returns `.standard`
    /// when no row exists yet (first-launch fallback).
    static func cachedTier(
        for userId: UUID,
        in context: ModelContext
    ) -> AbuseThresholds.AccountTier {
        let descriptor = FetchDescriptor<AccountRiskState>(
            predicate: #Predicate { $0.userId == userId }
        )
        return (try? context.fetch(descriptor))?.first?.tier ?? .standard
    }

    // MARK: - Heuristic helpers

    /// Rough proxy for "actions in the last N minutes" — sums RateLimitWindow
    /// counts whose windows overlap the time range.
    private static func recentActionCount(
        userId: UUID,
        sinceMinutes: Int,
        in context: ModelContext
    ) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(sinceMinutes) * 60)
        let descriptor = FetchDescriptor<RateLimitWindow>(
            predicate: #Predicate { $0.userId == userId && $0.windowStartedAt >= cutoff }
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return rows.reduce(0) { $0 + $1.count }
    }

    private static func hasRepeatedContent(
        userId: UUID,
        in context: ModelContext
    ) -> Bool {
        let cutoff = Date().addingTimeInterval(-86_400)
        let descriptor = FetchDescriptor<Post>(
            predicate: #Predicate { $0.authorId == userId && $0.timestamp >= cutoff }
        )
        let posts = (try? context.fetch(descriptor)) ?? []
        let captions = posts
            .map { $0.caption.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let counts = Dictionary(captions.map { ($0, 1) }, uniquingKeysWith: +)
        return counts.values.contains { $0 >= 3 }
    }

    private static func recentReportsAgainst(
        userId: UUID,
        in context: ModelContext
    ) -> Int {
        let cutoff = Date().addingTimeInterval(-86_400)
        let descriptor = FetchDescriptor<ContentReport>()
        let reports = (try? context.fetch(descriptor)) ?? []
        // Existing ContentReport stores `contentId` (not author). To map
        // a content row to its author we'd need a join; for the local
        // heuristic we count distinct reporters of *any* content ID
        // owned by the user across recent posts/comments.
        let postDescriptor = FetchDescriptor<Post>(
            predicate: #Predicate { $0.authorId == userId && $0.timestamp >= cutoff }
        )
        let userPostIds = Set(((try? context.fetch(postDescriptor)) ?? []).map(\.id))
        let commentDescriptor = FetchDescriptor<Comment>(
            predicate: #Predicate { $0.authorId == userId && $0.timestamp >= cutoff }
        )
        let userCommentIds = Set(((try? context.fetch(commentDescriptor)) ?? []).map(\.id))
        let userContentIds = userPostIds.union(userCommentIds)

        let recentReports = reports.filter {
            $0.createdAt >= cutoff && userContentIds.contains($0.contentId)
        }
        return Set(recentReports.map(\.reporterId)).count
    }

    private static func hasMentionFlood(
        userId: UUID,
        in context: ModelContext
    ) -> Bool {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let descriptor = FetchDescriptor<Post>(
            predicate: #Predicate { $0.authorId == userId && $0.timestamp >= cutoff }
        )
        let posts = (try? context.fetch(descriptor)) ?? []
        let mentionFloodCount = posts.filter { $0.taggedUsernames.count >= 10 }.count
        return mentionFloodCount >= 3
    }

    private static func hasIdenticalVoiceNoteDurations(
        userId: UUID,
        in context: ModelContext
    ) -> Bool {
        let cutoff = Date().addingTimeInterval(-86_400)

        // Combine voice-note durations from posts + audio-comment durations
        // so a bot pattern doesn't slip through by mixing surfaces.
        let postDescriptor = FetchDescriptor<Post>(
            predicate: #Predicate { $0.authorId == userId && $0.timestamp >= cutoff }
        )
        let posts = (try? context.fetch(postDescriptor)) ?? []
        let postDurations = posts.compactMap { $0.voiceNoteDuration }

        let commentDescriptor = FetchDescriptor<Comment>(
            predicate: #Predicate { $0.authorId == userId && $0.timestamp >= cutoff }
        )
        let comments = (try? context.fetch(commentDescriptor)) ?? []
        let commentDurations = comments.compactMap { $0.audioDurationSeconds }

        let durations = postDurations + commentDurations
        guard durations.count >= 5 else { return false }
        // Bucket durations into 0.5s buckets — any bucket with ≥5 hits = flag.
        let buckets = Dictionary(durations.map { (Int($0 * 2), 1) }, uniquingKeysWith: +)
        return buckets.values.contains { $0 >= 5 }
    }

    /// "More restrictive of two tiers wins." If score-based says
    /// throttled but base says trusted, we throttle (risk overrides
    /// trust). If score-based says standard but base says probationary,
    /// we keep probationary (trust isn't earned yet).
    private static func restrict(
        _ a: AbuseThresholds.AccountTier,
        by b: AbuseThresholds.AccountTier
    ) -> AbuseThresholds.AccountTier {
        let order: [AbuseThresholds.AccountTier] = [.paused, .throttled, .probationary, .standard, .trusted]
        let aIdx = order.firstIndex(of: a) ?? order.count - 1
        let bIdx = order.firstIndex(of: b) ?? order.count - 1
        return order[min(aIdx, bIdx)]
    }

    private static func upsertState(
        userId: UUID,
        score: Int,
        tier: AbuseThresholds.AccountTier,
        signals: [AbuseThresholds.RiskSignal],
        in context: ModelContext
    ) {
        let descriptor = FetchDescriptor<AccountRiskState>(
            predicate: #Predicate { $0.userId == userId }
        )
        let signalsJoined = signals.map(\.rawValue).joined(separator: ",")
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.score = score
            existing.tier = tier
            existing.recentSignals = signalsJoined
            existing.lastEvaluatedAt = .init()
        } else {
            let row = AccountRiskState(
                userId: userId,
                score: score,
                tier: tier,
                recentSignals: signalsJoined
            )
            context.insert(row)
        }
        try? context.save()
    }
}
