// LaunchRouter — design v4.3 §2 Smart Contextual Landing.
// 15-priority dispatcher that decides where a cold launch should land.

import Foundation
import SwiftData

/// Tab identity local to the router — kept independent of AppState.Tab so the
/// router can be tested without dragging in app-wide state.
enum LandingTabHint: String, Equatable {
    case home
    case friends
    case clubs
    case discover
}

enum LandingTarget: Equatable {
    case activeWorkout
    case post(id: UUID)
    case messagesThread(threadId: UUID)
    case friendsFeedAtPost(postId: UUID)
    case friendsActivity
    case friends
    case discoverWatch
    case homeWeekend
    case homeLiveStrip
    case home
    case lastSurface(LandingTabHint)
}

struct LaunchContext {
    var now: Date = .init()
    var hasActiveWorkout: Bool = false
    var deepLink: DeepLink? = nil
    var lastBackgroundedAt: Date? = nil
    var lastSurface: LandingTabHint? = nil
    var taggedPostInLast6h: UUID? = nil
    var taggedPostViewed: Bool = false
    var unreadDMInLast30m: UUID? = nil
    var friendPostInLast20m: (postId: UUID, authorFollowed: Bool)? = nil
    var atSavedGym: Bool = false
    var lastWorkoutAt: Date? = nil
    var unreadReactionsCount: Int = 0
    var friendJustFinishedWithin10m: Bool = false
    var accountCreatedAt: Date = .init()
    var followCount: Int = 0
    var workoutsInLast14d: Int = 0
    var activeFriendsCount: Int = 0
    var liveFriendsCount: Int = 0

    enum DeepLink: Equatable {
        case post(UUID)
        case dmThread(UUID)
        case friendsAtPost(UUID)
        case taggedPost(UUID)
        case profile(UUID)
        case crew(UUID)
        case discoverWatch
        case settings
    }

    var isWeekendMorning: Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let weekday = cal.component(.weekday, from: now) // 1 = Sunday, 7 = Saturday
        let hour = cal.component(.hour, from: now)
        return (weekday == 1 || weekday == 7) && hour < 13
    }

    var accountAgeDays: Int {
        Int(now.timeIntervalSince(accountCreatedAt) / 86_400)
    }

    var inPostWorkoutWindow: Bool {
        guard let last = lastWorkoutAt else { return false }
        return now.timeIntervalSince(last) < 60 * 60
    }

    var reopenedWithin5Min: Bool {
        guard let last = lastBackgroundedAt else { return false }
        return now.timeIntervalSince(last) < 5 * 60
    }
}

enum LaunchRouter {
    static func decide(_ ctx: LaunchContext) -> (target: LandingTarget, ruleIndex: Int) {
        // 1. Active workout → resume.
        if ctx.hasActiveWorkout { return (.activeWorkout, 1) }

        // 2. Notification deep-link wins next.
        if let link = ctx.deepLink {
            switch link {
            case .post(let id): return (.post(id: id), 2)
            case .dmThread(let id): return (.messagesThread(threadId: id), 2)
            case .friendsAtPost(let id), .taggedPost(let id):
                return (.friendsFeedAtPost(postId: id), 2)
            case .profile, .crew, .settings: break
            case .discoverWatch: return (.discoverWatch, 2)
            }
        }

        // 3. Re-open within 5 min → return to last surface.
        if ctx.reopenedWithin5Min, let surface = ctx.lastSurface {
            return (.lastSurface(surface), 3)
        }

        // 4. Tagged in last 6 h, not yet viewed.
        if let postId = ctx.taggedPostInLast6h, !ctx.taggedPostViewed {
            return (.friendsFeedAtPost(postId: postId), 4)
        }

        // 5. Unread DM in last 30 min.
        if let threadId = ctx.unreadDMInLast30m {
            return (.messagesThread(threadId: threadId), 5)
        }

        // 6. Friend posted within last 20 min AND user follows.
        if let entry = ctx.friendPostInLast20m, entry.authorFollowed {
            return (.friendsFeedAtPost(postId: entry.postId), 6)
        }

        // 7. At saved gym AND no workout in last 4 h.
        let fourHoursAgo = ctx.now.addingTimeInterval(-4 * 60 * 60)
        let noRecentWorkout = ctx.lastWorkoutAt.map { $0 < fourHoursAgo } ?? true
        if ctx.atSavedGym && noRecentWorkout {
            return (.home, 7)
        }

        // 8. Post-workout window (60 min) → Friends Activity.
        if ctx.inPostWorkoutWindow {
            return (.friendsActivity, 8)
        }

        // 9. Unread reactions ≥3 OR friend just finished within 10 min.
        if ctx.unreadReactionsCount >= 3 || ctx.friendJustFinishedWithin10m {
            return (.friends, 9)
        }

        // 10. New user (<7 days) OR <5 friends → Discover Watch.
        if ctx.accountAgeDays < 7 || ctx.followCount < 5 {
            return (.discoverWatch, 10)
        }

        // 11. Lurker (no workouts 14d) AND <3 active friends → Discover Watch.
        if ctx.workoutsInLast14d == 0 && ctx.activeFriendsCount < 3 {
            return (.discoverWatch, 11)
        }

        // 12. Weekend morning → Home (events).
        if ctx.isWeekendMorning {
            return (.homeWeekend, 12)
        }

        // 13. Weekday idle (no live signals + no recent reactions + workouts) → Discover Watch.
        let weekdayIdle = !ctx.isWeekendMorning
            && ctx.unreadReactionsCount == 0
            && ctx.liveFriendsCount == 0
            && ctx.workoutsInLast14d == 0
        if weekdayIdle {
            return (.discoverWatch, 13)
        }

        // 14. Friends are live (≥2).
        if ctx.liveFriendsCount >= 2 {
            return (.homeLiveStrip, 14)
        }

        // 15. Default → Home.
        return (.home, 15)
    }
}
