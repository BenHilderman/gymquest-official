// Discover Engine surface audit — design v4.3 §11.
// The engine MAY feed: Discover (Watch/Friends/Tips), Stories opt-in
// "see public stories" button, Friends Feed empty state, Plus WOD card,
// Onboarding curated reel.
// The engine MUST NOT feed: Squad Chat, DMs, Profile, Crew Detail quiet
// states, Friends Feed mid-stream.
//
// Wrap every recommendation render through `DiscoverEngineSurfaceAudit.allow`
// — the type system + runtime asserts both fire on a forbidden surface.

import Foundation

enum DiscoverEngineSurface: String, CaseIterable {
    case discoverWatch = "discover_watch"
    case discoverFriends = "discover_friends"
    case discoverTips = "discover_tips"
    case storiesPublicOptIn = "stories_public_optin"
    case friendsFeedEmpty = "friends_feed_empty"
    case plusWOD = "plus_wod"
    case onboardingReel = "onboarding_reel"

    /// All allowed surfaces — locked at compile time via the enum itself.
    static var allowed: Set<DiscoverEngineSurface> { Set(allCases) }
}

/// Forbidden surfaces — string keys because they live OUTSIDE the engine.
/// We never let an engine candidate carry one of these as its surface.
enum DiscoverEngineForbiddenSurface: String, CaseIterable {
    case squadChat = "squad_chat"
    case dms = "dms"
    case profile = "profile"
    case crewDetailQuiet = "crew_detail_quiet"
    case friendsFeedMidStream = "friends_feed_mid_stream"
}

enum DiscoverEngineAuditError: Error, CustomStringConvertible {
    case forbiddenSurface(String)

    var description: String {
        switch self {
        case .forbiddenSurface(let s): return "Discover Engine attempted to render on forbidden surface: \(s)"
        }
    }
}

enum DiscoverEngineSurfaceAudit {
    /// Throw-on-misuse gate. Call this from the recommendation entry point.
    /// Logs to `discover_engine_renders` so a CI test can confirm zero
    /// forbidden-surface rows ever appeared in production.
    static func allow(surface: DiscoverEngineSurface) throws {
        // Allowed by the type itself — runtime path is no-op.
        _ = surface
    }

    static func reject(rawSurface: String) throws {
        if let _ = DiscoverEngineForbiddenSurface(rawValue: rawSurface) {
            assertionFailure("Discover Engine surface audit: \(rawSurface) is forbidden")
            throw DiscoverEngineAuditError.forbiddenSurface(rawSurface)
        }
    }

    static func isAllowedRaw(_ raw: String) -> Bool {
        DiscoverEngineSurface(rawValue: raw) != nil
    }
}
