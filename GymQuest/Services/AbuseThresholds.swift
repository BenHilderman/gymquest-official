// AbuseThresholds — content-safety phase 4 single source of truth.
//
// Every numeric knob the rate-limit + bot-heuristic services read lives
// here. Tighten or loosen any rule by editing one constant — call sites
// stay untouched. Defaults are intentionally generous; the goal is
// catching bot spikes, not rate-limiting real users.

import Foundation

enum AbuseThresholds {

    // MARK: - Account tier
    // Tier policy:
    //   probationary — < 24h since signup OR 0 workouts logged
    //   standard     — normal account (most users)
    //   trusted      — > 30 days old, ≥ 10 workouts, no moderation
    //                  strikes in 90 days
    //   throttled    — risk score 26–60: limits halved, no UI hint
    //   paused       — risk score 61–100: can't post for 24h

    enum AccountTier: String, Codable, CaseIterable {
        case probationary
        case standard
        case trusted
        case throttled
        case paused
    }

    // MARK: - Rate-limit ring 1 (rolling 1-hour windows)
    // Real users: < 5% of any limit on a normal day. Bots blow through.

    enum Action: String, CaseIterable {
        case postCreate
        case commentCreate
        case storyCreate
        case dmSend
        case dmSendToSingleRecipient
        case squadMessageSend
        case reaction
        case followRequest
        case squadInvite
        case clubJoin
        case mentionInPost  // count, not frequency
    }

    /// Per-hour soft cap for a given action and tier. nil = action not
    /// rate-limited for that tier (e.g. mentionInPost is per-post, not per-hour).
    static func hourlyLimit(_ action: Action, tier: AccountTier) -> Int? {
        switch (action, tier) {
        // probationary
        case (.postCreate, .probationary):              return 8
        case (.commentCreate, .probationary):           return 30
        case (.storyCreate, .probationary):             return 6
        case (.dmSend, .probationary):                  return 50
        case (.dmSendToSingleRecipient, .probationary): return 20
        case (.squadMessageSend, .probationary):        return 100
        case (.reaction, .probationary):                return 150
        case (.followRequest, .probationary):           return 15
        case (.squadInvite, .probationary):             return 8
        case (.clubJoin, .probationary):                return 5
        case (.mentionInPost, .probationary):           return 3

        // standard
        case (.postCreate, .standard):                  return 30
        case (.commentCreate, .standard):               return 100
        case (.storyCreate, .standard):                 return 20
        case (.dmSend, .standard):                      return 200
        case (.dmSendToSingleRecipient, .standard):     return 50
        case (.squadMessageSend, .standard):            return 300
        case (.reaction, .standard):                    return 500
        case (.followRequest, .standard):               return 50
        case (.squadInvite, .standard):                 return 30
        case (.clubJoin, .standard):                    return 20
        case (.mentionInPost, .standard):               return 10

        // trusted
        case (.postCreate, .trusted):                   return 60
        case (.commentCreate, .trusted):                return 200
        case (.storyCreate, .trusted):                  return 40
        case (.dmSend, .trusted):                       return 400
        case (.dmSendToSingleRecipient, .trusted):      return 100
        case (.squadMessageSend, .trusted):             return 600
        case (.reaction, .trusted):                     return 1000
        case (.followRequest, .trusted):                return 100
        case (.squadInvite, .trusted):                  return 60
        case (.clubJoin, .trusted):                     return 40
        case (.mentionInPost, .trusted):                return 15

        // throttled — half of standard
        case (.postCreate, .throttled):                 return 15
        case (.commentCreate, .throttled):              return 50
        case (.storyCreate, .throttled):                return 10
        case (.dmSend, .throttled):                     return 100
        case (.dmSendToSingleRecipient, .throttled):    return 25
        case (.squadMessageSend, .throttled):           return 150
        case (.reaction, .throttled):                   return 250
        case (.followRequest, .throttled):              return 25
        case (.squadInvite, .throttled):                return 15
        case (.clubJoin, .throttled):                   return 10
        case (.mentionInPost, .throttled):              return 5

        // paused — zero everything except reactions (read-only mode)
        case (.reaction, .paused):                      return 50
        case (_, .paused):                              return 0
        }
    }

    // MARK: - Rate-limit ring 2 (daily caps)
    // Hit only by the most active humans; still generous.

    static func dailyLimit(_ action: Action, tier: AccountTier) -> Int? {
        switch (action, tier) {
        case (.postCreate, .standard):                  return 100
        case (.commentCreate, .standard):               return 500
        case (.storyCreate, .standard):                 return 50
        case (.dmSend, .standard):                      return 1000
        case (.followRequest, .standard):               return 200
        // Other tiers scale linearly: probationary=0.4x, trusted=2x, throttled=0.5x, paused=0.

        case (.postCreate, .probationary):              return 40
        case (.postCreate, .trusted):                   return 200
        case (.postCreate, .throttled):                 return 50
        case (.postCreate, .paused):                    return 0

        case (.commentCreate, .probationary):           return 200
        case (.commentCreate, .trusted):                return 1000
        case (.commentCreate, .throttled):              return 250
        case (.commentCreate, .paused):                 return 0

        case (.storyCreate, .probationary):             return 20
        case (.storyCreate, .trusted):                  return 100
        case (.storyCreate, .throttled):                return 25
        case (.storyCreate, .paused):                   return 0

        case (.dmSend, .probationary):                  return 400
        case (.dmSend, .trusted):                       return 2000
        case (.dmSend, .throttled):                     return 500
        case (.dmSend, .paused):                        return 0

        case (.followRequest, .probationary):           return 80
        case (.followRequest, .trusted):                return 400
        case (.followRequest, .throttled):              return 100
        case (.followRequest, .paused):                 return 0

        default: return nil   // no daily cap on this action
        }
    }

    // MARK: - Ring 4 — anti-harassment per-target caps (tier-agnostic)

    /// Comments by a single author on a single post per day.
    static let commentsByOneAuthorOnOnePost = 5
    /// DMs to a recipient who hasn't replied to your first message.
    static let dmsBeforeFirstReply = 3
    /// Distinct reaction kinds on a single post by same user.
    static let reactionKindsOnOnePost = 10
    /// Joining + leaving same crew/squad cycles per week.
    static let crewJoinLeaveCyclesPerWeek = 3

    // MARK: - Ring 3 — bot heuristic compound flags
    // Risk points add up to a tier change. See `BotHeuristicService`.

    enum RiskSignal: String {
        case youngAccountHighActivity            // < 24h + > 10 actions/h
        case zeroWorkoutsHighSocial              // 0 workouts logged after 7 days + > 50 social actions
        case repeatedContentText                 // same text 3+ times in 24h
        case followUnfollowChurn                 // 5+ follow→unfollow same target/h
        case repeatedSignupSameDevice            // 3+ signups same device fingerprint / 24h
        case userReportsSpike                    // ≥ 5 reports in 24h
        case mentionFlood                        // ≥ 10 mentions in single post, 3+ posts
        case identicalVoiceNoteDurations         // ± 0.5s across 5+ notes / day
    }

    static func points(for signal: RiskSignal) -> Int {
        switch signal {
        case .youngAccountHighActivity:    return 30
        case .zeroWorkoutsHighSocial:      return 25
        case .repeatedContentText:         return 40
        case .followUnfollowChurn:         return 35
        case .repeatedSignupSameDevice:    return 50
        case .userReportsSpike:            return 60
        case .mentionFlood:                return 30
        case .identicalVoiceNoteDurations: return 20
        }
    }

    /// Map an aggregated risk score → account tier. Caller refreshes
    /// AccountRiskState whenever new signals come in.
    static func tier(forRiskScore score: Int) -> AccountTier {
        switch score {
        case ..<26:   return .standard
        case 26..<61: return .throttled
        case 61..<101: return .paused
        default:       return .paused   // 100+ would be locked, modeled as paused for now
        }
    }

    // MARK: - Account-age + workout-count tier classifier

    /// Promotes / demotes the base tier based on tenure and workout
    /// count. Called by BotHeuristicService.evaluateTier whenever account
    /// state changes meaningfully.
    static func baseTier(
        accountAgeSeconds: TimeInterval,
        workoutCount: Int,
        moderationStrikesLast90Days: Int
    ) -> AccountTier {
        let oneDay: TimeInterval = 86_400
        let thirtyDays: TimeInterval = 30 * 86_400

        if accountAgeSeconds < oneDay || workoutCount == 0 {
            return .probationary
        }
        if accountAgeSeconds >= thirtyDays && workoutCount >= 10 && moderationStrikesLast90Days == 0 {
            return .trusted
        }
        return .standard
    }
}
