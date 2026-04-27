//
//  AliveComponents.swift
//  GymQuest
//
//  Phase 1 primitives for the Alive release. Every other phase reads from
//  the same `PresenceState` source-of-truth via these components — never
//  fork the ring or pulse logic.
//
//  Spec rule: Active is universal. Location is friend-scoped. The ring on
//  any avatar reads only from `PresenceStatus`, which strangers can see;
//  gym detail (`gymId` / `gymName`) is gated by the AtMyGymBanner pipeline.
//

import SwiftUI
import SwiftData

// MARK: - Snapshot of a presence row

/// Lookup-only projection of `UserPresenceState`. Components never write
/// through this — they read for ring + pulse decisions.
struct PresenceSnapshot: Equatable {
    let status: PresenceStatus
    let startedAt: Date?
    let gymName: String?

    var showsRing: Bool {
        switch status {
        case .arriving, .training, .resting, .finishedRecently: return true
        case .idle, .ghost: return false
        }
    }

    var ringColor: Color {
        switch status {
        case .arriving: return AlivePresence.gold
        case .training, .resting, .finishedRecently: return AlivePresence.green
        case .idle, .ghost: return .clear
        }
    }

    /// `arriving` and `training/resting` pulse; `finishedRecently` is steady.
    var pulses: Bool {
        switch status {
        case .arriving, .training, .resting: return true
        default: return false
        }
    }
}

// MARK: - Color tokens (the only three colors Alive uses)

enum AlivePresence {
    /// Active workout. Used for ring + tab bar dot for social activity.
    static let green = Color(red: 0.20, green: 0.78, blue: 0.45)
    /// Self-action suggested (geofence, arriving). Tab dot for "+", ring for arriving.
    static let gold = Color(red: 0.98, green: 0.74, blue: 0.20)
    /// Personal attention (Activity replies, reactions waiting).
    static let red = Color(red: 0.95, green: 0.30, blue: 0.30)
}

// MARK: - PresenceLookup environment

/// Closure that resolves `userId → PresenceSnapshot?`. Provided once at
/// `ContentView` root, consumed everywhere via `@Environment(\.presenceLookup)`.
typealias PresenceLookup = (UUID) -> PresenceSnapshot?

private struct PresenceLookupKey: EnvironmentKey {
    static let defaultValue: PresenceLookup = { _ in nil }
}

extension EnvironmentValues {
    var presenceLookup: PresenceLookup {
        get { self[PresenceLookupKey.self] }
        set { self[PresenceLookupKey.self] = newValue }
    }
}

/// Provider that wraps a SwiftData `@Query` of presence rows and exposes a
/// dictionary lookup. Drop near the root of the tab tree.
struct PresenceLookupProvider<Content: View>: View {
    @Query private var states: [UserPresenceState]
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        let dict = Dictionary(uniqueKeysWithValues: states.map { ($0.userId, snapshot(from: $0)) })
        let lookup: PresenceLookup = { dict[$0] }
        return content()
            .environment(\.presenceLookup, lookup)
    }

    private func snapshot(from state: UserPresenceState) -> PresenceSnapshot {
        PresenceSnapshot(
            status: state.status,
            startedAt: state.startedAt,
            gymName: state.gymName
        )
    }
}

// MARK: - Presence ring (every avatar in the app)

struct PresenceRingModifier: ViewModifier {
    let userId: UUID
    let size: CGFloat
    @Environment(\.presenceLookup) private var lookup
    @State private var pulse: Bool = false

    func body(content: Content) -> some View {
        let snapshot = lookup(userId)
        // Render the ring as a non-hit-testing overlay that extends past
        // the content via negative padding. Crucially we DON'T resize the
        // content or wrap it in a fixed `size + 6` frame — that was
        // forcing every ringed avatar to occupy 6pt extra of layout
        // space, which shifted post headers / strips / cards. Now:
        // content renders at its natural size, ring floats outside its
        // bounds when active, zero layout impact when idle.
        content
            .overlay {
                if let snap = snapshot, snap.showsRing {
                    Circle()
                        .stroke(snap.ringColor, lineWidth: 2)
                        .padding(-3)
                        .opacity(snap.pulses ? (pulse ? 0.55 : 1.0) : 1.0)
                        .animation(
                            snap.pulses ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true) : .default,
                            value: pulse
                        )
                        .onAppear { pulse = true }
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// Layer the universal Alive presence ring around any avatar. Reads
    /// from the `presenceLookup` environment — no per-call wiring required.
    func presenceRing(_ userId: UUID, size: CGFloat = 46) -> some View {
        modifier(PresenceRingModifier(userId: userId, size: size))
    }
}

// MARK: - Live pulse for tab icons

/// Sub-state per tab — drives whether to show the colored dot and what color.
enum LiveTabSignal {
    case none
    case social   // green — social activity (Friends / Clubs)
    case personal // red — replies / reactions waiting
    case selfHint // gold — geofence / suggested action

    var color: Color? {
        switch self {
        case .none: return nil
        case .social: return AlivePresence.green
        case .personal: return AlivePresence.red
        case .selfHint: return AlivePresence.gold
        }
    }
}

struct LivePulseTabIcon: ViewModifier {
    let signal: LiveTabSignal
    @State private var pulse: Bool = false

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if let color = signal.color {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .opacity(pulse ? 0.55 : 1.0)
                    .scaleEffect(pulse ? 0.9 : 1.0)
                    .offset(x: 3, y: -3)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
            }
        }
    }
}

extension View {
    func liveTabPulse(_ signal: LiveTabSignal) -> some View {
        modifier(LivePulseTabIcon(signal: signal))
    }
}

// MARK: - Ambient header strip

/// Pinned to the top of any social surface (Today, Clubs list, club detail,
/// Activity). Three lines max. Hides when both counts are 0.
struct AmbientHeaderStrip: View {
    let friendCount: Int
    let clubmateCount: Int
    let avatarPeek: [UUID]
    var onTap: () -> Void = {}

    private var isHidden: Bool { friendCount == 0 && clubmateCount == 0 }

    var body: some View {
        if isHidden {
            EmptyView()
        } else {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(AlivePresence.green)
                        .frame(width: 7, height: 7)
                    Text(headline)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    avatarStack
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(GQColors.surfaceBase)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(GQColors.borderDefault.opacity(0.5), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var headline: String {
        var parts: [String] = []
        if friendCount > 0 { parts.append("\(friendCount) friend\(friendCount == 1 ? "" : "s")") }
        if clubmateCount > 0 { parts.append("\(clubmateCount) clubmate\(clubmateCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ") + " lifting now"
    }

    @ViewBuilder
    private var avatarStack: some View {
        let peek = Array(avatarPeek.prefix(3))
        if !peek.isEmpty {
            HStack(spacing: -6) {
                ForEach(Array(peek.enumerated()), id: \.element) { _, id in
                    Circle()
                        .fill(GQColors.deepBlue.opacity(0.18))
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle().stroke(GQColors.surfaceBase, lineWidth: 1.5)
                        )
                        .presenceRing(id, size: 18)
                }
            }
        }
    }
}
