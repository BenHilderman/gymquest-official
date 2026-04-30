// UserBlockButton + AppealSheetView — content-safety phase 3C.
//
// Block button is a subtle toggle exposed on other-user profiles.
// Tap → confirm dialog → ContentReportService.block(...) → button flips
// to "blocked" state.
//
// AppealSheetView surfaces held content for the author so they can
// appeal a moderation rejection. Lists the reason + a "this was OK"
// button that flips a local appeal flag (server canonical happens via
// the Phase 2 trigger ladder).

import SwiftUI
import SwiftData

struct UserBlockButton: View {
    let currentUserId: UUID
    let targetUserId: UUID
    let targetDisplayName: String

    @Environment(\.modelContext) private var modelContext
    @State private var isBlocked: Bool = false
    @State private var confirming = false

    var body: some View {
        Button {
            confirming = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isBlocked ? "person.fill.xmark" : "person.crop.circle.badge.xmark")
                    .font(.system(size: 13, weight: .semibold))
                Text(isBlocked ? "blocked" : "block")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isBlocked ? GQColors.textTertiary : GQColors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(GQColors.adaptiveOverlay(isBlocked ? 0.10 : 0.06)))
        }
        .buttonStyle(.plain)
        .onAppear {
            isBlocked = ContentReportService.isBlocked(
                userId: currentUserId,
                blockedUserId: targetUserId,
                in: modelContext
            )
        }
        .confirmationDialog(
            isBlocked
                ? "unblock \(targetDisplayName.lowercased())?"
                : "block \(targetDisplayName.lowercased())?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button(isBlocked ? "unblock" : "block",
                   role: isBlocked ? nil : .destructive) {
                toggleBlock()
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text(isBlocked
                 ? "you'll see their content and DMs again."
                 : "they won't be able to DM, mention, or tag you. their content disappears from your feed.")
        }
    }

    private func toggleBlock() {
        if isBlocked {
            ContentReportService.unblock(
                userId: currentUserId,
                blockedUserId: targetUserId,
                in: modelContext
            )
            isBlocked = false
        } else {
            ContentReportService.block(
                userId: currentUserId,
                blockedUserId: targetUserId,
                in: modelContext
            )
            isBlocked = true
        }
    }
}

/// Appeal sheet — lists the user's content currently held for review
/// (Comment.isHiddenByModeration == true OR moderationVerdict == "rejected").
/// Tap "appeal this" sets the local appeal flag; canonical decision
/// happens server-side.
struct AppealSheetView: View {
    let currentUserId: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var heldComments: [Comment]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("held content")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("done") { dismiss() }
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        let held = heldComments.filter { $0.authorId == currentUserId && $0.isHiddenByModeration }
        if held.isEmpty {
            emptyState
        } else {
            List(held, id: \.id) { comment in
                row(for: comment)
            }
            .listStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 44))
                .foregroundStyle(GQGradients.primary)
            Text("nothing held")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(GQColors.textPrimary)
            Text("your content is in the clear.")
                .font(.system(size: 13))
                .foregroundColor(GQColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for comment: Comment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                Text(comment.timestamp.formatted(.relative(presentation: .named)))
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
                Spacer()
                Button("appeal this") {
                    appeal(comment: comment)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(GQColors.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(GQColors.adaptiveOverlay(0.08)))
            }
            if !comment.content.isEmpty {
                Text(comment.content)
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textSecondary)
                    .lineLimit(3)
            }
            if comment.mediaKind == .audio {
                Label("voice note", systemImage: "waveform")
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
            } else if comment.mediaKind == .photo {
                Label("photo", systemImage: "photo")
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func appeal(comment: Comment) {
        // Local appeal — flips the moderation verdict to a pending appeal
        // state. Server canonical decision happens via the Phase 2 trigger
        // ladder + a manual review queue. Once the server resolves the
        // appeal, the moderation_verdict column updates and the comment
        // un-hides naturally.
        comment.moderationVerdictRaw = "appealed"
        try? modelContext.save()
    }
}
