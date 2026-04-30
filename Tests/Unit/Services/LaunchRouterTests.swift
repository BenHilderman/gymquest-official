import XCTest
@testable import GymQuest

/// LaunchRouter — design v4.3 §2 Smart Contextual Landing.
/// One test per rule (15 rules) plus the default fallback.
final class LaunchRouterTests: XCTestCase {

    // MARK: rule 1

    func testRule1_activeWorkoutWins() {
        var ctx = LaunchContext()
        ctx.hasActiveWorkout = true
        // Even with deep link present, active workout overrides.
        ctx.deepLink = .post(UUID())
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 1)
        XCTAssertEqual(target, .activeWorkout)
    }

    // MARK: rule 2

    func testRule2_deepLinkPost() {
        var ctx = LaunchContext()
        let postId = UUID()
        ctx.deepLink = .post(postId)
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 2)
        XCTAssertEqual(target, .post(id: postId))
    }

    func testRule2_deepLinkDM() {
        var ctx = LaunchContext()
        let threadId = UUID()
        ctx.deepLink = .dmThread(threadId)
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 2)
        XCTAssertEqual(target, .messagesThread(threadId: threadId))
    }

    // MARK: rule 3

    func testRule3_reopenWithin5Min() {
        var ctx = LaunchContext()
        ctx.lastBackgroundedAt = ctx.now.addingTimeInterval(-60)
        ctx.lastSurface = .friends
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 3)
        XCTAssertEqual(target, .lastSurface(.friends))
    }

    func testRule3_doesNotApplyAfter5Min() {
        var ctx = LaunchContext()
        ctx.lastBackgroundedAt = ctx.now.addingTimeInterval(-6 * 60)
        ctx.lastSurface = .friends
        // With no other signals, falls through to rule 10 (new user) — accountAge < 7d default.
        let (_, idx) = LaunchRouter.decide(ctx)
        XCTAssertNotEqual(idx, 3)
    }

    // MARK: rule 4

    func testRule4_taggedNotYetViewed() {
        var ctx = LaunchContext()
        let postId = UUID()
        ctx.taggedPostInLast6h = postId
        ctx.taggedPostViewed = false
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 4)
        XCTAssertEqual(target, .friendsFeedAtPost(postId: postId))
    }

    func testRule4_taggedAlreadyViewed_doesNotApply() {
        var ctx = LaunchContext()
        ctx.taggedPostInLast6h = UUID()
        ctx.taggedPostViewed = true
        let (_, idx) = LaunchRouter.decide(ctx)
        XCTAssertNotEqual(idx, 4)
    }

    // MARK: rule 5

    func testRule5_unreadDM() {
        var ctx = LaunchContext()
        let threadId = UUID()
        ctx.unreadDMInLast30m = threadId
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 5)
        XCTAssertEqual(target, .messagesThread(threadId: threadId))
    }

    // MARK: rule 6

    func testRule6_friendPostedRecentlyAndFollowed() {
        var ctx = LaunchContext()
        let postId = UUID()
        ctx.friendPostInLast20m = (postId, true)
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 6)
        XCTAssertEqual(target, .friendsFeedAtPost(postId: postId))
    }

    func testRule6_friendPostedButNotFollowed_doesNotApply() {
        var ctx = LaunchContext()
        ctx.friendPostInLast20m = (UUID(), false)
        let (_, idx) = LaunchRouter.decide(ctx)
        XCTAssertNotEqual(idx, 6)
    }

    // MARK: rule 7

    func testRule7_atSavedGymWithNoRecentWorkout() {
        var ctx = LaunchContext()
        ctx.atSavedGym = true
        ctx.lastWorkoutAt = ctx.now.addingTimeInterval(-5 * 60 * 60)  // 5h ago
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 7)
        XCTAssertEqual(target, .home)
    }

    func testRule7_atSavedGymWithRecentWorkout_doesNotApply() {
        var ctx = LaunchContext()
        ctx.atSavedGym = true
        ctx.lastWorkoutAt = ctx.now.addingTimeInterval(-1 * 60 * 60)  // 1h ago
        let (_, idx) = LaunchRouter.decide(ctx)
        XCTAssertNotEqual(idx, 7)
    }

    // MARK: rule 8

    func testRule8_postWorkoutWindow() {
        var ctx = LaunchContext()
        ctx.lastWorkoutAt = ctx.now.addingTimeInterval(-10 * 60)  // 10m ago
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 8)
        XCTAssertEqual(target, .friendsActivity)
    }

    // MARK: rule 9

    func testRule9_unreadReactionsAtLeast3() {
        var ctx = LaunchContext()
        ctx.unreadReactionsCount = 3
        // Defeat rule 8 by clearing post-workout window
        ctx.lastWorkoutAt = ctx.now.addingTimeInterval(-90 * 60)
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 9)
        XCTAssertEqual(target, .friends)
    }

    func testRule9_friendJustFinished() {
        var ctx = LaunchContext()
        ctx.friendJustFinishedWithin10m = true
        ctx.lastWorkoutAt = ctx.now.addingTimeInterval(-90 * 60)
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 9)
        XCTAssertEqual(target, .friends)
    }

    // MARK: rule 10

    func testRule10_newUser() {
        var ctx = LaunchContext()
        ctx.followCount = 10  // bypass <5 friends
        ctx.accountCreatedAt = ctx.now.addingTimeInterval(-3 * 86_400)  // 3 days
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 10)
        XCTAssertEqual(target, .discoverWatch)
    }

    func testRule10_lessThan5Friends() {
        var ctx = LaunchContext()
        ctx.accountCreatedAt = ctx.now.addingTimeInterval(-30 * 86_400)
        ctx.followCount = 2
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 10)
        XCTAssertEqual(target, .discoverWatch)
    }

    // MARK: rule 11

    func testRule11_lurker() {
        var ctx = LaunchContext()
        ctx.accountCreatedAt = ctx.now.addingTimeInterval(-60 * 86_400)
        ctx.followCount = 10
        ctx.workoutsInLast14d = 0
        ctx.activeFriendsCount = 1
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 11)
        XCTAssertEqual(target, .discoverWatch)
    }

    // MARK: rule 12

    func testRule12_weekendMorningRoute() {
        // Build a Saturday morning at 9 AM
        var components = DateComponents()
        components.year = 2025; components.month = 1; components.day = 4  // Sat
        components.hour = 9
        let saturday = Calendar(identifier: .gregorian).date(from: components)!

        var ctx = LaunchContext(now: saturday)
        ctx.accountCreatedAt = saturday.addingTimeInterval(-60 * 86_400)
        ctx.followCount = 10
        ctx.workoutsInLast14d = 5
        ctx.activeFriendsCount = 5
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 12)
        XCTAssertEqual(target, .homeWeekend)
    }

    // MARK: rule 13

    func testRule13_weekdayIdle() {
        // Weekday at 14:00, no live signals, no recent reactions, no workouts.
        var components = DateComponents()
        components.year = 2025; components.month = 1; components.day = 8  // Wed
        components.hour = 14
        let weekday = Calendar(identifier: .gregorian).date(from: components)!

        var ctx = LaunchContext(now: weekday)
        ctx.accountCreatedAt = weekday.addingTimeInterval(-60 * 86_400)
        ctx.followCount = 10
        ctx.workoutsInLast14d = 0
        ctx.activeFriendsCount = 5  // bypasses rule 11 (lurker requires <3 active)
        ctx.liveFriendsCount = 0
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 13)
        XCTAssertEqual(target, .discoverWatch)
    }

    // MARK: rule 14

    func testRule14_friendsLive() {
        // Mid-week, established user, friends live.
        var components = DateComponents()
        components.year = 2025; components.month = 1; components.day = 8  // Wed
        components.hour = 19
        let weekday = Calendar(identifier: .gregorian).date(from: components)!

        var ctx = LaunchContext(now: weekday)
        ctx.accountCreatedAt = weekday.addingTimeInterval(-60 * 86_400)
        ctx.followCount = 10
        ctx.workoutsInLast14d = 5
        ctx.activeFriendsCount = 5
        ctx.liveFriendsCount = 3
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 14)
        XCTAssertEqual(target, .homeLiveStrip)
    }

    // MARK: rule 15

    func testRule15_default() {
        // Established weekday user with no signals.
        var components = DateComponents()
        components.year = 2025; components.month = 1; components.day = 8
        components.hour = 14
        let weekday = Calendar(identifier: .gregorian).date(from: components)!

        var ctx = LaunchContext(now: weekday)
        ctx.accountCreatedAt = weekday.addingTimeInterval(-60 * 86_400)
        ctx.followCount = 10
        ctx.workoutsInLast14d = 5
        ctx.activeFriendsCount = 5
        ctx.liveFriendsCount = 1
        let (target, idx) = LaunchRouter.decide(ctx)
        XCTAssertEqual(idx, 15)
        XCTAssertEqual(target, .home)
    }
}
