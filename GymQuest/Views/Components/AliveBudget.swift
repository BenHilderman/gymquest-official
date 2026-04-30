// AliveBudget — design v4.3 §9 "max 3 Alive elements per page at once".
// A view modifier that lets a screen declare priority for its alive elements;
// surplus elements degrade gracefully (presence ring fades to gray, animation pauses).

import SwiftUI

enum AlivePriority: Int, Comparable {
    case low = 0
    case medium = 1
    case high = 2
    case critical = 3
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

@MainActor
final class AliveBudgetTracker: ObservableObject {
    @Published private(set) var awarded: Set<UUID> = []
    private var enrolled: [(id: UUID, priority: AlivePriority)] = []
    private let maxConcurrent: Int

    init(maxConcurrent: Int = 3) { self.maxConcurrent = maxConcurrent }

    func enroll(id: UUID, priority: AlivePriority) {
        if let idx = enrolled.firstIndex(where: { $0.id == id }) {
            enrolled[idx] = (id, priority)
        } else {
            enrolled.append((id, priority))
        }
        recomputeAwards()
    }

    func withdraw(id: UUID) {
        enrolled.removeAll { $0.id == id }
        recomputeAwards()
    }

    private func recomputeAwards() {
        let top = enrolled
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.id.uuidString > rhs.id.uuidString
            }
            .prefix(maxConcurrent)
            .map(\.id)
        awarded = Set(top)
    }
}

struct AliveBudgetKey: EnvironmentKey {
    static let defaultValue: AliveBudgetTracker? = nil
}

extension EnvironmentValues {
    var aliveBudget: AliveBudgetTracker? {
        get { self[AliveBudgetKey.self] }
        set { self[AliveBudgetKey.self] = newValue }
    }
}

struct AliveBudgetEnvelope<Content: View>: View {
    @StateObject private var tracker = AliveBudgetTracker()
    let content: (AliveBudgetTracker) -> Content
    init(@ViewBuilder content: @escaping (AliveBudgetTracker) -> Content) {
        self.content = content
    }
    var body: some View {
        content(tracker).environment(\.aliveBudget, tracker)
    }
}

struct AliveElementModifier: ViewModifier {
    let id: UUID
    let priority: AlivePriority
    @Environment(\.aliveBudget) private var budget
    @State private var awarded: Bool = true

    func body(content: Content) -> some View {
        content
            .opacity(awarded ? 1.0 : 0.5)
            .animation(.easeInOut(duration: 0.18), value: awarded)
            .task(id: id) {
                budget?.enroll(id: id, priority: priority)
                if let b = budget {
                    for await awardSet in b.$awarded.values {
                        awarded = awardSet.contains(id)
                    }
                }
            }
            .onDisappear { budget?.withdraw(id: id) }
    }
}

extension View {
    /// Mark this view as an Alive element competing for the page's budget.
    /// Surplus low-priority elements fade to 0.5 opacity and stop animating.
    func aliveElement(priority: AlivePriority = .medium, id: UUID = UUID()) -> some View {
        modifier(AliveElementModifier(id: id, priority: priority))
    }
}

/// Presence ring colour helper per design §9: green / purple / gray / ghost.
enum PresenceRingState: String {
    case live
    case recentlyFinished
    case inactive
    case ghost
    case none

    var color: Color {
        switch self {
        case .live: return GQColors.success
        case .recentlyFinished: return GQColors.vividPurple
        case .inactive: return GQColors.borderSubtle
        case .ghost: return GQColors.surfaceSecondary
        case .none: return .clear
        }
    }

    var ringWidth: CGFloat {
        switch self {
        case .live: return 2.5
        case .recentlyFinished: return 2.0
        case .inactive: return 1.0
        case .ghost: return 0.5
        case .none: return 0
        }
    }

    var pulses: Bool { self == .live }

    /// Decay rule: live ring 5 min after last ping, recently-finished 60 min.
    static func from(lastPingAt: Date?, isGhost: Bool, now: Date = .init()) -> PresenceRingState {
        if isGhost { return .ghost }
        guard let ping = lastPingAt else { return .none }
        let elapsed = now.timeIntervalSince(ping)
        if elapsed <= 5 * 60 { return .live }
        if elapsed <= 60 * 60 { return .recentlyFinished }
        return .inactive
    }
}

/// Standard reaction vocabulary per design §9 — custom Lift + standard.
enum LiftReaction: String, CaseIterable, Identifiable {
    case monke = "🦍"  // locked in / monke mode
    case goat = "🐐"   // GOAT
    case dying = "💀"
    case hard = "😤"
    case respect = "🤝"
    case clean = "🥶"
    case fire = "🔥"
    case flex = "💪"
    case eyes = "👀"

    var id: String { rawValue }

    var meaning: String {
        switch self {
        case .monke: return "locked in"
        case .goat: return "GOAT"
        case .dying: return "dying"
        case .hard: return "going hard"
        case .respect: return "respect"
        case .clean: return "clean lift"
        case .fire: return "fire"
        case .flex: return "flex"
        case .eyes: return "watching"
        }
    }
}
