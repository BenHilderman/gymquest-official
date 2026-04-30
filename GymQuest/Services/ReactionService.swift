// ReactionService — content-safety phase 4 helper.
//
// Reactions get inserted from 10+ surfaces (PostCard, Explore, Discover,
// Alive, ScrollFeedClip, etc.). Centralizing the create flow into one
// service is a wider refactor; this helper instead exposes the rate-limit
// gate as a single call so each insertion site can guard with one line:
//
//     guard ReactionService.allowReact(userId: me, postId: post.id, in: ctx)
//         else { return }
//     modelContext.insert(reaction)

import Foundation
import SwiftData

@MainActor
enum ReactionService {

    /// Returns `true` when the user is under their per-target reaction
    /// cap and may insert a new reaction. `false` when rate-limited
    /// (caller silently drops). Targets are post / workoutCard / etc.
    /// Use `targetKey = id.uuidString` so the per-target cap applies
    /// per-post, not per-user globally.
    @discardableResult
    static func allowReact(
        userId: UUID,
        targetId: UUID,
        in context: ModelContext
    ) -> Bool {
        let tier = BotHeuristicService.cachedTier(for: userId, in: context)
        let decision = RateLimitService.allow(
            .reaction,
            by: userId,
            targetKey: targetId.uuidString,
            tier: tier,
            in: context
        )
        return !decision.isBlocking
    }
}
