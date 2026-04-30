// DiscoverStoriesService — locked spec §2 (Backfill ON list).
//
// Resolves the "from your gym / trending public stories" stream that
// powers two surfaces:
//   1. StoryViewerView caught-up overlay's "see public stories" opt-in
//      (when the user has watched all friends' stories)
//   2. StoriesThinBackfillStrip on Home (when fewer than 3 friends have
//      an active story)
//
// Both surfaces audit through `DiscoverEngineSurfaceAudit.storiesPublicOptIn`
// before rendering, so the engine knows it's allowed to feed here.
//
// The actual "public" candidate set is intentionally derived from local
// SwiftData first — Story rows authored by non-followed users with
// `audience == .public` in the last 24h. When the server-side feed lands
// (Phase 1), the same call site can swap in a Supabase fetch without any
// caller changes.

import Foundation
import SwiftData

@MainActor
enum DiscoverStoriesService {

    /// Returns the public-story stream the user opted into. Filters:
    ///   • not the current user's own stories
    ///   • author is NOT in the user's follow graph
    ///   • `audience == .public`
    ///   • not deleted
    ///   • not expired (within the 24h window the model already enforces)
    /// Sorted most-recent-first so the viewer surfaces the freshest
    /// public lift the moment the user opts in.
    static func publicStories(
        currentUserId: UUID,
        followedIds: Set<UUID>,
        in context: ModelContext
    ) -> [Story] {
        let now = Date()
        let descriptor = FetchDescriptor<Story>(
            sortBy: [SortDescriptor(\.postedAt, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor) else { return [] }
        return all.filter { story in
            !story.isDeleted
                && story.expiresAt > now
                && story.audience == .public
                && story.authorId != currentUserId
                && !followedIds.contains(story.authorId)
        }
    }
}
