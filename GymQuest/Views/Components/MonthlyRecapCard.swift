// MonthlyRecapCard — content-psychology pass.
//
// Bridges the daily-streak / weekly-squad / yearly-recap cadence with a
// monthly identity ritual. Shown the first time the user opens the app
// in a new month, summarizing the prior month's 4 stats in a compact
// share-able card. Persists "seen" state per month so it never repeats.
//
// Layered ritual goal: every cadence (daily / weekly / monthly /
// quarterly / yearly) has its own surface, so the user is constantly
// near a small win — strongest predictor of habit retention per the
// research on streak architecture.

import SwiftUI
import SwiftData

struct MonthlyRecapCard: View {
    let stats: MonthlyRecapStats
    var onShare: () -> Void = {}
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(spacing: 18) {
            // Header
            VStack(spacing: 4) {
                Text(stats.monthName.lowercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
                    .textCase(.uppercase)
                Text("your month in 4")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(GQColors.textPrimary)
            }

            // 2x2 stat grid
            HStack(spacing: 12) {
                statTile(label: "sessions", value: "\(stats.sessionCount)")
                statTile(label: "days shown", value: "\(stats.distinctDays)")
            }
            HStack(spacing: 12) {
                statTile(label: "tons lifted", value: String(format: "%.1f", stats.tonsLifted))
                statTile(label: "top exercise", value: stats.topExercise)
            }

            if let line = stats.identityLine {
                Text(line)
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .padding(.horizontal, 24)
            }

            HStack(spacing: 10) {
                Button("share") { onShare() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .frame(width: 110, height: 44)
                    .background(GQColors.adaptiveOverlay(0.06), in: Capsule())
                Button("done") { onDismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(width: 140)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 26)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(GQColors.surfaceBase)
        )
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(GQColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(GQColors.textTertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(GQColors.adaptiveOverlay(0.04))
        )
    }
}

struct MonthlyRecapStats {
    let monthName: String     // "april"
    let sessionCount: Int
    let distinctDays: Int
    let tonsLifted: Double
    let topExercise: String
    let identityLine: String?
}

@MainActor
enum MonthlyRecapResolver {

    /// Build stats for the prior calendar month from local Workout rows.
    /// Returns nil if zero sessions — better to skip the recap than
    /// surface a sad "0" card.
    static func priorMonthStats(in context: ModelContext, now: Date = Date()) -> MonthlyRecapStats? {
        let cal = Calendar(identifier: .gregorian)
        guard let priorMonth = cal.date(byAdding: .month, value: -1, to: now) else { return nil }
        guard let monthInterval = cal.dateInterval(of: .month, for: priorMonth) else { return nil }

        let descriptor = FetchDescriptor<Workout>(
            predicate: #Predicate { w in
                w.date >= monthInterval.start && w.date < monthInterval.end
            }
        )
        let monthWorkouts = (try? context.fetch(descriptor)) ?? []
        guard !monthWorkouts.isEmpty else { return nil }

        // Distinct days — meaningful even when sessions count is high.
        let dayKeys = Set(monthWorkouts.map { cal.startOfDay(for: $0.date) })

        // Total tons — sum totalVolume / 2000 (lb→tons).
        let totalLb = monthWorkouts.reduce(0.0) { $0 + $1.totalVolume }
        let tons = totalLb / 2000.0

        // Top exercise — most-frequent across sets.
        var exerciseCounts: [String: Int] = [:]
        for workout in monthWorkouts {
            for exercise in workout.exercises {
                exerciseCounts[exercise.name, default: 0] += exercise.sets.count
            }
        }
        let topExercise = exerciseCounts
            .max(by: { $0.value < $1.value })?.key ?? "—"

        // Identity line — quiet, factual.
        let identityLine: String? = {
            if dayKeys.count >= 24 { return "you barely missed a day. respect." }
            if dayKeys.count >= 16 { return "consistent. that's the part that compounds." }
            if dayKeys.count >= 8  { return "you showed up. keep building." }
            return nil
        }()

        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "LLLL"
        let monthName = monthFormatter.string(from: monthInterval.start).lowercased()

        return MonthlyRecapStats(
            monthName: monthName,
            sessionCount: monthWorkouts.count,
            distinctDays: dayKeys.count,
            tonsLifted: tons,
            topExercise: topExercise.lowercased(),
            identityLine: identityLine
        )
    }

    /// Has the user already seen the recap for the prior month? Stored
    /// in UserDefaults keyed by "YYYY-MM" so we never repeat.
    static func hasSeen(monthName: String) -> Bool {
        UserDefaults.standard.bool(forKey: seenKey(monthName: monthName))
    }

    static func markSeen(monthName: String) {
        UserDefaults.standard.set(true, forKey: seenKey(monthName: monthName))
    }

    private static func seenKey(monthName: String) -> String {
        "monthlyRecapSeen-\(monthName)"
    }
}
