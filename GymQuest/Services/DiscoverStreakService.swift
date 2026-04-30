// DiscoverStreakService — design v4.3 §3A
// Tracks weekly counters: workouts saved, tips applied, clips reacted, etc.
// Sync target: identity (XP/level/Profile Year So Far).

import Foundation

enum DiscoverStreakKind: String, Codable, CaseIterable {
    case workoutSaved = "workout_saved"
    case tipApplied = "tip_applied"
    case clipReacted = "clip_reacted"
    case creatorFollowed = "creator_followed"
    case workoutTried = "workout_tried"

    var label: String {
        switch self {
        case .workoutSaved: return "workouts saved"
        case .tipApplied: return "tips applied"
        case .clipReacted: return "clips reacted"
        case .creatorFollowed: return "creators followed"
        case .workoutTried: return "workouts tried"
        }
    }
}

struct DiscoverStreakSnapshot: Equatable {
    var weekStarting: Date
    var counts: [DiscoverStreakKind: Int] = [:]

    var summaryLine: String {
        let parts = counts
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(2)
            .map { "\($0.value) \($0.key.label) this week" }
        return parts.joined(separator: " · ")
    }
}

/// ISO week-start for a given date — top-level so it can be used in stored property
/// initializers (Swift forbids `Self.staticMethod()` there).
private func discoverStreakWeekStart(now: Date = .init()) -> Date {
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = .current
    let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
    return cal.date(from: comps) ?? now
}

@MainActor
final class DiscoverStreakService: ObservableObject {
    static let shared = DiscoverStreakService()
    @Published private(set) var snapshot = DiscoverStreakSnapshot(weekStarting: discoverStreakWeekStart())

    private init() {}

    static func weekStart(now: Date = .init()) -> Date {
        discoverStreakWeekStart(now: now)
    }

    func increment(_ kind: DiscoverStreakKind, by delta: Int = 1) {
        snapshot.counts[kind, default: 0] += delta
        Task { await persist(kind: kind, count: snapshot.counts[kind] ?? 0) }
    }

    func reset(forNewWeek: Date) {
        snapshot = .init(weekStarting: forNewWeek)
    }

    private func persist(kind: DiscoverStreakKind, count: Int) async {
        let row: [String: Any] = [
            "kind": kind.rawValue,
            "week_starting": Self.iso(snapshot.weekStarting),
            "count": count
        ]
        await SupabaseUpsertBridge.upsert(table: "discover_streak_counters", row: row,
                                          onConflict: "user_id,kind,week_starting")
    }

    private static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: d)
    }
}
