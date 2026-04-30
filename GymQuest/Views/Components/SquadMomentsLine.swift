// SquadMomentsLine — design v4.3 + Item A locked spec.
// Slim rotating line below squad header showing real squad data only.
// Hides entirely when no notable activity exists ("quiet is honest").

import SwiftUI

struct SquadMomentsLine: View {
    let displayText: String?
    var onTap: () -> Void = {}

    var body: some View {
        if let text = displayText {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: iconForText(text))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GQGradients.primary)
                    Text(text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(GQColors.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(GQColors.overlayLight)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func iconForText(_ text: String) -> String {
        if text.contains("trained at") { return "person.2.fill" }
        if text.contains("PR") { return "trophy.fill" }
        if text.contains("streak") { return "flame.fill" }
        return "sparkles"
    }
}

/// Rotating-pool helper for SquadMomentsLine. Returns one of three real-data
/// stats per call, or nil if all three are below threshold (quiet squad).
enum SquadMomentsCompute {
    /// Picks one stat per open. Inputs are pre-aggregated by the caller so
    /// the helper stays cheap and pure. `seed` makes the pick session-stable
    /// when the caller passes a `@State RotationSeed.index`; falls back to
    /// random when omitted (legacy callers).
    static func pickStat(
        coPresenceLine: String?,   // e.g. "you and marcus trained at goodlife · 2 days ago"
        prsThisMonthCount: Int,
        streakLeaderName: String?,
        streakLeaderDays: Int,
        seed: Int? = nil
    ) -> String? {
        var pool: [String] = []

        if let coPresence = coPresenceLine, !coPresence.isEmpty {
            pool.append(coPresence)
        }
        if prsThisMonthCount > 0 {
            pool.append("squad PRs this month: \(prsThisMonthCount)")
        }
        if let leader = streakLeaderName, streakLeaderDays > 0 {
            pool.append("longest squad streak: \(leader.lowercased()) · \(streakLeaderDays) days")
        }

        guard !pool.isEmpty else { return nil }
        if let seed { return pool[seed % pool.count] }
        return pool.randomElement()
    }
}
