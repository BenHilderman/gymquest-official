// StoriesThinBackfillStrip — locked spec section 2 (Backfill ON list).
//
// "Stories row on Home/Feed when thin — fewer than 3 friends with active
// stories triggers labeled backfill creator/trending bubbles."
//
// Rendered as a slim 1-line strip under FriendsRow, never appended into
// FriendsRow itself: the spec elsewhere (Slot 4 / Item D) is explicit that
// presence rings = follow + live trust signal and must not be diluted by
// backfill avatars. Keeping backfill in its own visually-demoted strip
// honors both rules.
//
// The discover-stories source itself is wired in the next pass (same
// deferred path as StoryViewerView's caught-up overlay). The audit hook
// fires on tap so analytics + RLS gating are in place ahead of content.

import SwiftUI

struct StoriesThinBackfillStrip: View {
    /// Number of friends with an active story in the last 24h. The strip
    /// hides at 3+ (per spec: only renders when "thin").
    let activeFriendStoryCount: Int
    var onTapSeeStories: () -> Void = {}

    var body: some View {
        if activeFriendStoryCount < 3 {
            Button(action: onTapSeeStories) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GQGradients.primary)
                    Text("from your gym · catch up on public stories")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(GQColors.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(GQColors.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(GQColors.overlayLight)
                )
            }
            .buttonStyle(.plain)
        }
    }
}
