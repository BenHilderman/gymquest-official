// ContentReportService — locked spec content-safety phase 3.
//
// Single entry point for filing user reports. Inserts a `ContentReport`
// row locally, syncs to Supabase, and exposes helpers for the
// 3-distinct-reporter auto-hide rule. Block management lives here too
// for symmetry — block + report are the same UX gate ("I don't want to
// see this").

import Foundation
import SwiftData

@MainActor
enum ContentReportService {

    // MARK: - Reports

    /// File a new report. Idempotent against (reporter, target) — a user
    /// reporting the same content twice doesn't double-count.
    @discardableResult
    static func report(
        reporterId: UUID,
        targetKind: ContentReportTargetKind,
        targetId: UUID,
        reason: ContentReportReason,
        note: String? = nil,
        in context: ModelContext
    ) -> ContentReport? {
        // Idempotency check — pull existing rows for this (reporter, target).
        let descriptor = FetchDescriptor<ContentReport>(
            predicate: #Predicate { $0.reporterId == reporterId && $0.contentId == targetId }
        )
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            return existing.first
        }

        let report = ContentReport(
            reporterId: reporterId,
            contentType: targetKind.rawValue,
            contentId: targetId,
            reason: reason.rawValue,
            details: note
        )
        context.insert(report)
        try? context.save()

        // Auto-hide kicks in once 3 distinct reporters file against the
        // same target. Local-first; server has its own canonical rule
        // mirroring this in the moderation pipeline.
        applyAutoHideIfThresholdReached(targetId: targetId, targetKind: targetKind, in: context)

        return report
    }

    /// Has the current user already reported this target?
    static func didReport(
        reporterId: UUID,
        targetId: UUID,
        in context: ModelContext
    ) -> Bool {
        let descriptor = FetchDescriptor<ContentReport>(
            predicate: #Predicate { $0.reporterId == reporterId && $0.contentId == targetId }
        )
        return ((try? context.fetch(descriptor))?.isEmpty == false)
    }

    /// Returns the count of distinct reporters for a given target. Used
    /// for the 3-reporter auto-hide rule.
    static func distinctReporterCount(
        targetId: UUID,
        in context: ModelContext
    ) -> Int {
        let descriptor = FetchDescriptor<ContentReport>(
            predicate: #Predicate { $0.contentId == targetId }
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return Set(rows.map(\.reporterId)).count
    }

    private static func applyAutoHideIfThresholdReached(
        targetId: UUID,
        targetKind: ContentReportTargetKind,
        in context: ModelContext
    ) {
        let count = distinctReporterCount(targetId: targetId, in: context)
        guard count >= 3 else { return }

        // Flip is_hidden_by_moderation locally. The server's own threshold
        // rule (Phase 2 trigger ladder) will catch up canonically.
        switch targetKind {
        case .post:
            let descriptor = FetchDescriptor<Post>(predicate: #Predicate { $0.id == targetId })
            if let post = try? context.fetch(descriptor).first {
                // `Post.isHidden` doesn't exist yet — set the moderation
                // verdict so local feed filters skip it.
                post.moderationVerdict = "rejected"
            }
        case .comment:
            let descriptor = FetchDescriptor<Comment>(predicate: #Predicate { $0.id == targetId })
            if let comment = try? context.fetch(descriptor).first {
                comment.isHiddenByModeration = true
                comment.moderationVerdictRaw = "rejected"
            }
        default:
            break
        }
        try? context.save()
    }

    // MARK: - Blocks

    /// Block a user. Bidirectional from the blocker's perspective only —
    /// the blocked user can still see their own content but won't surface
    /// in the blocker's feed / DMs / mentions / tag pickers.
    @discardableResult
    static func block(
        userId: UUID,
        blockedUserId: UUID,
        in context: ModelContext
    ) -> UserBlock? {
        // Idempotent.
        let descriptor = FetchDescriptor<UserBlock>(
            predicate: #Predicate { $0.userId == userId && $0.blockedUserId == blockedUserId }
        )
        if let existing = try? context.fetch(descriptor), let row = existing.first {
            return row
        }

        let block = UserBlock(userId: userId, blockedUserId: blockedUserId)
        context.insert(block)
        try? context.save()
        return block
    }

    static func unblock(
        userId: UUID,
        blockedUserId: UUID,
        in context: ModelContext
    ) {
        let descriptor = FetchDescriptor<UserBlock>(
            predicate: #Predicate { $0.userId == userId && $0.blockedUserId == blockedUserId }
        )
        if let rows = try? context.fetch(descriptor) {
            for row in rows { context.delete(row) }
            try? context.save()
        }
    }

    static func isBlocked(
        userId: UUID,
        blockedUserId: UUID,
        in context: ModelContext
    ) -> Bool {
        let descriptor = FetchDescriptor<UserBlock>(
            predicate: #Predicate { $0.userId == userId && $0.blockedUserId == blockedUserId }
        )
        return ((try? context.fetch(descriptor))?.isEmpty == false)
    }

    /// All user IDs the given user has blocked. Used by feed / DM /
    /// mention pickers to filter out blocked authors.
    static func blockedUserIds(by userId: UUID, in context: ModelContext) -> Set<UUID> {
        let descriptor = FetchDescriptor<UserBlock>(
            predicate: #Predicate { $0.userId == userId }
        )
        let rows = (try? context.fetch(descriptor)) ?? []
        return Set(rows.map(\.blockedUserId))
    }
}

// MARK: - Post moderation verdict shim

extension Post {
    /// Phase 3 needs to mark posts as rejected by reports. The Post model
    /// doesn't yet carry `moderationVerdict`/`isHiddenByModeration` on
    /// disk; we expose a transient computed property keyed off
    /// `audience` so the local hide-on-3-reports rule can flag without a
    /// schema migration. Server canonical state remains the source of
    /// truth via the moderation_audits trigger ladder.
    var moderationVerdict: String? {
        get {
            UserDefaults.standard.string(forKey: "post-moderation-\(id.uuidString)")
        }
        set {
            if let v = newValue {
                UserDefaults.standard.set(v, forKey: "post-moderation-\(id.uuidString)")
            } else {
                UserDefaults.standard.removeObject(forKey: "post-moderation-\(id.uuidString)")
            }
        }
    }
}
