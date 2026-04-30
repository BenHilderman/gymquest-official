// ProfileV43SuggestionCard — design v4.3 Item B locked spec.
// Single suggestion card surfaced on the user's own Profile when post count = 0.
// Surfaces the strongest available signal from real workout data and offers
// a one-tap publish that creates a throwback-flagged post.

import SwiftUI

struct ProfileV43SuggestionCard: View {
    let signalLine: String       // e.g. "your bench PR · 2 weeks ago"
    let detailLine: String?      // e.g. "225 × 5"
    var onPost: () -> Void = {}
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
                Text("post your first proof")
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundColor(GQColors.textSecondary)
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(GQColors.textTertiary)
                        .padding(4)
                }
                .buttonStyle(.plain)
            }
            Text(signalLine)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(GQColors.textPrimary)
            if let detail = detailLine {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(GQColors.textSecondary)
            }
            Button(action: onPost) {
                Text("post →")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(GQGradients.primary))
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(GQColors.overlayLight)
        )
        .padding(.horizontal, 16)
    }
}

/// Picks the single strongest signal for the suggestion card.
/// Priority: best PR > longest workout > most recent workout > nil.
enum ProfileSuggestionPicker {
    struct Suggestion {
        let workout: Workout
        let signalLine: String
        let detailLine: String?
        let daysAgo: Int
    }

    static func pick(from workouts: [Workout]) -> Suggestion? {
        guard !workouts.isEmpty else { return nil }
        let now = Date()

        // Priority 1 — best PR among recent workouts (within last 30 days)
        let recentWorkouts = workouts.filter { now.timeIntervalSince($0.date) <= 30 * 86_400 }
        if let prWorkout = recentWorkouts.first(where: { !$0.prEvents.isEmpty }) {
            let topPR = prWorkout.prEvents.max { $0.newValue < $1.newValue }
            let days = Int(now.timeIntervalSince(prWorkout.date) / 86_400)
            return Suggestion(
                workout: prWorkout,
                signalLine: "your \(topPR?.exerciseName.lowercased() ?? "lift") PR · \(prettyDays(days))",
                detailLine: topPR.map { "\(Int($0.newValue))" },
                daysAgo: days
            )
        }

        // Priority 2 — longest workout this month
        let thisMonth = workouts.filter { now.timeIntervalSince($0.date) <= 30 * 86_400 }
        if let longest = thisMonth.max(by: { $0.duration < $1.duration }) {
            let days = Int(now.timeIntervalSince(longest.date) / 86_400)
            return Suggestion(
                workout: longest,
                signalLine: "your longest workout this month · \(prettyDays(days))",
                detailLine: "\(longest.duration) min · \(longest.type.rawValue.lowercased())",
                daysAgo: days
            )
        }

        // Priority 3 — most recent workout overall
        if let recent = workouts.first {
            let days = Int(now.timeIntervalSince(recent.date) / 86_400)
            return Suggestion(
                workout: recent,
                signalLine: "your most recent workout · \(prettyDays(days))",
                detailLine: "\(recent.duration) min · \(recent.type.rawValue.lowercased())",
                daysAgo: days
            )
        }

        return nil
    }

    private static func prettyDays(_ days: Int) -> String {
        if days == 0 { return "today" }
        if days == 1 { return "1 day ago" }
        if days < 7 { return "\(days) days ago" }
        if days < 14 { return "1 week ago" }
        if days < 30 { return "\(days / 7) weeks ago" }
        return "\(days / 30) months ago"
    }
}
