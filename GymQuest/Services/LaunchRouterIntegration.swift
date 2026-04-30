// LaunchRouter ↔ AppState bridge.
// Wires the cold-launch + foreground-refresh decision into the existing
// `AppState` tab + flow types. Drops in alongside the legacy 2-state
// branch in `ContentView.onAppear` — replace, don't dual-run.

import Foundation
import SwiftData

@MainActor
enum LaunchRouterIntegration {
    /// Build a `LaunchContext` from the live ModelContext + presence cache.
    /// Pure read — no side effects.
    static func makeContext(
        userId: UUID?,
        modelContext: ModelContext?,
        presenceStates: [UserPresenceState] = [],
        deepLink: LaunchContext.DeepLink? = nil,
        lastBackgroundedAt: Date? = nil,
        lastSurface: LandingTabHint? = nil,
        atSavedGym: Bool = false,
        accountCreatedAt: Date = .init()
    ) -> LaunchContext {
        var ctx = LaunchContext(now: .init())
        ctx.deepLink = deepLink
        ctx.lastBackgroundedAt = lastBackgroundedAt
        ctx.lastSurface = lastSurface
        ctx.atSavedGym = atSavedGym
        ctx.accountCreatedAt = accountCreatedAt

        guard let _ = userId, let _ = modelContext else { return ctx }

        // Populate live signals from presence cache. Real wiring in app code
        // delegates to `FriendActivityService` / `FriendsRecapService`.
        ctx.liveFriendsCount = countLive(presenceStates, now: ctx.now)
        ctx.activeFriendsCount = countActive(presenceStates)
        return ctx
    }

    private static func countLive(_ states: [UserPresenceState], now: Date) -> Int {
        var count = 0
        for state in states {
            guard state.status == .training, let started = state.startedAt else { continue }
            if now.timeIntervalSince(started) < 3 * 3600 { count += 1 }
        }
        return count
    }

    private static func countActive(_ states: [UserPresenceState]) -> Int {
        var count = 0
        for state in states {
            switch state.status {
            case .arriving, .training, .resting: count += 1
            default: break
            }
        }
        return count
    }

    /// Decide a landing target. Pass-through to `LaunchRouter.decide` —
    /// kept here so call sites don't import the router directly and the
    /// telemetry logging is centralized.
    static func decide(_ ctx: LaunchContext) -> LandingTarget {
        let (target, ruleIndex) = LaunchRouter.decide(ctx)
        // Telemetry hook: call sites typically forward this to the analytics
        // pipeline. Logged here at debug level to ease tuning.
        #if DEBUG
        print("[launch-router] rule=\(ruleIndex) target=\(target)")
        #endif
        return target
    }
}

/// AppState.Tab ↔ LandingTabHint mapping. Free function so it doesn't pull
/// AppState into the LaunchRouter module.
@MainActor
func mapTabToLandingHint(_ tab: AppState.Tab) -> LandingTabHint {
    switch tab {
    case .friends: return .friends
    case .clubs: return .clubs
    case .discover: return .discover
    case .today: return .home
    case .home, .coach, .activity, .profile: return .home
    }
}
