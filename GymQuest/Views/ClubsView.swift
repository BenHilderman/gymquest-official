//
//  ClubsView.swift
//  GymQuest
//
//  Extracted from FeedView.swift for modularization.
//

import SwiftUI
import SwiftData
import AVKit
import MapKit
import PhotosUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Club Seeder

struct ClubSeeder {
    static func seedIfNeeded(modelContext: ModelContext, userId: UUID) {
        let descriptor = FetchDescriptor<Club>(predicate: #Predicate { $0.parentClubId == nil })
        let existing = (try? modelContext.fetchCount(descriptor)) ?? 0

        let users = SocialSeeder.fakeUsers

        // Seed clubs + posts + challenges if first run
        if existing == 0 {
            seedClubs(modelContext: modelContext, userId: userId, users: users)
        }

        // Seed events separately so existing installs get them without data wipe
        let eventDescriptor = FetchDescriptor<ClubEvent>()
        let existingEvents = (try? modelContext.fetchCount(eventDescriptor)) ?? 0
        if existingEvents == 0 {
            seedEvents(modelContext: modelContext, userId: userId, users: users)
        }

        try? modelContext.save()
    }

    private static func seedClubs(modelContext: ModelContext, userId: UUID, users: [(id: UUID, name: String, username: String)]) {
        let cal = Calendar.current

        // Queen's Run Club
        let runClub = Club(
            name: "Queen's Run Club",
            clubDescription: "Weekly group runs around Kingston. All paces welcome.",
            location: "Kingston, ON",
            latitude: 44.2253,
            longitude: -76.4951,
            creatorId: users[0].id,
            memberIds: [userId] + users.prefix(6).map(\.id),
            joinType: .open,
            memberCount: 178,
            isVerified: true,
            tags: ["running", "cardio", "kingston"],
            category: .running
        )
        modelContext.insert(runClub)

        // Run Club channels
        for name in ["5K Group", "Long Distance", "Trail Runners"] {
            let channel = Club(
                name: name,
                clubDescription: "",
                creatorId: users[0].id,
                memberIds: [userId] + users.prefix(3).map(\.id),
                memberCount: Int.random(in: 20...60),
                parentClubId: runClub.id
            )
            modelContext.insert(channel)
        }

        // Kingston Pickup Basketball
        let basketball = Club(
            name: "Kingston Pickup Basketball",
            clubDescription: "Pickup games around Kingston. Drop in anytime.",
            location: "Kingston, ON",
            latitude: 44.2312,
            longitude: -76.4860,
            creatorId: users[1].id,
            memberIds: [userId] + users.prefix(5).map(\.id),
            joinType: .open,
            memberCount: 124,
            tags: ["basketball", "pickup", "kingston"],
            category: .basketball
        )
        modelContext.insert(basketball)

        for name in ["West End Courts", "Queen's Gym"] {
            let channel = Club(
                name: name,
                clubDescription: "",
                creatorId: users[1].id,
                memberIds: [userId] + users.prefix(2).map(\.id),
                memberCount: Int.random(in: 20...50),
                parentClubId: basketball.id
            )
            modelContext.insert(channel)
        }

        // Queen's Powerlifting
        let powerlifting = Club(
            name: "Queen's Powerlifting",
            clubDescription: "Squat, bench, deadlift. Compete or just train with us.",
            location: "Kingston, ON",
            latitude: 44.2280,
            longitude: -76.4935,
            creatorId: users[2].id,
            memberIds: [userId] + users.prefix(6).map(\.id),
            joinType: .open,
            memberCount: 156,
            isVerified: true,
            tags: ["powerlifting", "strength", "kingston"],
            category: .weightlifting
        )
        modelContext.insert(powerlifting)

        // Kingston Cycling Group
        let cycling = Club(
            name: "Kingston Cycling Group",
            clubDescription: "Road rides and gravel routes around the Kingston area.",
            location: "Kingston, ON",
            latitude: 44.2300,
            longitude: -76.4800,
            creatorId: users[3].id,
            memberIds: users.prefix(4).map(\.id),
            joinType: .open,
            memberCount: 92,
            tags: ["cycling", "road", "kingston"],
            category: .cycling
        )
        modelContext.insert(cycling)

        // Campus Yoga
        let yoga = Club(
            name: "Campus Yoga",
            clubDescription: "Free flow sessions on campus. Mats provided.",
            location: "Kingston, ON",
            latitude: 44.2260,
            longitude: -76.4970,
            creatorId: users[4].id,
            memberIds: users.prefix(5).map(\.id),
            joinType: .open,
            memberCount: 210,
            tags: ["yoga", "mindfulness", "kingston"],
            category: .yoga
        )
        modelContext.insert(yoga)

        // Queen's Intramural Soccer
        let soccer = Club(
            name: "Queen's Intramural Soccer",
            clubDescription: "Co-ed intramural soccer. Scrimmages every Thursday.",
            location: "Kingston, ON",
            latitude: 44.2240,
            longitude: -76.5010,
            creatorId: users[5].id,
            memberIds: users.prefix(4).map(\.id),
            joinType: .open,
            memberCount: 86,
            isVerified: true,
            tags: ["soccer", "intramural", "kingston"],
            category: .soccer
        )
        modelContext.insert(soccer)

        // Global clubs
        let homeGym = Club(
            name: "Home Gym Heroes",
            clubDescription: "For everyone training at home",
            creatorId: users[2].id,
            memberIds: users.prefix(4).map(\.id),
            joinType: .open,
            memberCount: 1420,
            tags: ["global"],
            category: .generalFitness
        )
        modelContext.insert(homeGym)

        let beginnerGains = Club(
            name: "Beginner Gains",
            clubDescription: "New to lifting? Start here",
            creatorId: users[6].id,
            memberIds: users.prefix(4).map(\.id),
            joinType: .open,
            memberCount: 3200,
            tags: ["global"],
            category: .weightlifting
        )
        modelContext.insert(beginnerGains)

        let prChasers = Club(
            name: "PR Chasers",
            clubDescription: "Chasing personal records every week",
            creatorId: users[7].id,
            memberIds: users.prefix(4).map(\.id),
            joinType: .open,
            memberCount: 890,
            tags: ["global"],
            category: .weightlifting
        )
        modelContext.insert(prChasers)

        // Seed memberships for user's clubs
        let userClubs = [runClub, basketball, powerlifting]
        for comm in userClubs {
            let userMembership = ClubMembership(
                userId: userId,
                clubId: comm.id,
                role: .member
            )
            modelContext.insert(userMembership)

            for (i, user) in users.prefix(6).enumerated() {
                guard comm.memberIds.contains(user.id) else { continue }
                let membership = ClubMembership(
                    userId: user.id,
                    clubId: comm.id,
                    role: i == 0 ? .admin : .member,
                    workoutPartnerStatus: [1, 2, 4].contains(i) ? .available : .notLooking
                )
                modelContext.insert(membership)
            }
        }

        // Seed challenges
        let runChallenge = ClubChallenge(
            clubId: runClub.id,
            title: "50km This Week",
            challengeDescription: "Log 50km of running before Sunday. Every km counts.",
            goalType: .distance,
            goalTarget: 50,
            currentProgress: 32,
            startDate: cal.date(byAdding: .day, value: -4, to: Date()) ?? Date(),
            endDate: cal.date(byAdding: .day, value: 3, to: Date()) ?? Date(),
            participantIds: [userId] + users.prefix(4).map(\.id)
        )
        modelContext.insert(runChallenge)

        let plChallenge = ClubChallenge(
            clubId: powerlifting.id,
            title: "Complete 20 Sets",
            challengeDescription: "Hit 20 total sets of squat, bench, or deadlift this week",
            goalType: .sets,
            goalTarget: 20,
            currentProgress: 13,
            startDate: cal.date(byAdding: .day, value: -3, to: Date()) ?? Date(),
            endDate: cal.date(byAdding: .day, value: 4, to: Date()) ?? Date(),
            participantIds: [userId] + users.prefix(5).map(\.id)
        )
        modelContext.insert(plChallenge)

        let bbChallenge = ClubChallenge(
            clubId: basketball.id,
            title: "5 Pickup Games This Month",
            challengeDescription: "Show up to 5 pickup sessions this month",
            goalType: .games,
            goalTarget: 5,
            currentProgress: 2,
            startDate: cal.date(byAdding: .day, value: -10, to: Date()) ?? Date(),
            endDate: cal.date(byAdding: .day, value: 20, to: Date()) ?? Date(),
            participantIds: [userId] + users.prefix(3).map(\.id)
        )
        modelContext.insert(bbChallenge)

        // Seed club posts
        let samplePosts: [(UUID, Int, String, ClubPostType)] = [
            (runClub.id, 0, "New 5K PR this morning! 22:14. The waterfront route hits different at sunrise", .achievement),
            (runClub.id, 2, "Anyone want to pace me for a 10K this weekend?", .lookingForPartner),
            (basketball.id, 1, "Last night's pickup game was insane. That buzzer-beater shot was unreal", .general),
            (basketball.id, 3, "Looking for a 5th for Tuesday evening games at the ARC", .lookingForPartner),
            (powerlifting.id, 4, "Hit 315 deadlift today. New PR by 10 lbs!", .achievement),
            (powerlifting.id, 5, "The platform was empty at 6am. Rare W", .general),
            (soccer.id, 7, "Thursday scrimmage was a 4-3 thriller. See everyone next week", .general),
        ]

        for (cid, userIdx, content, ptype) in samplePosts {
            let user = users[userIdx]
            let post = ClubPost(
                clubId: cid,
                authorId: user.id,
                authorName: user.name,
                authorUsername: user.username,
                postType: ptype,
                content: content,
                likeCount: Int.random(in: 2...18),
                commentCount: Int.random(in: 0...5),
                timestamp: Date().addingTimeInterval(Double.random(in: -86400...0))
            )
            modelContext.insert(post)
        }

        // Posts for global clubs
        let globalClubs = [homeGym, beginnerGains, prChasers]
        let globalPosts: [(String, Int, String, ClubPostType)] = [
            ("Home Gym Heroes", 8, "Finally got a squat rack in my garage. Game changer", .achievement),
            ("Home Gym Heroes", 6, "Resistance bands + bodyweight = underrated combo", .workout),
            ("Beginner Gains", 9, "Just finished my first ever full week of training!", .achievement),
            ("Beginner Gains", 3, "What's the difference between sumo and conventional deadlift?", .question),
            ("PR Chasers", 4, "315 squat at 165 bodyweight. PR by 10 lbs!", .achievement),
        ]

        for (commName, userIdx, content, ptype) in globalPosts {
            if let comm = globalClubs.first(where: { $0.name == commName }) {
                let user = users[userIdx]
                let post = ClubPost(
                    clubId: comm.id,
                    authorId: user.id,
                    authorName: user.name,
                    authorUsername: user.username,
                    postType: ptype,
                    content: content,
                    likeCount: Int.random(in: 3...22),
                    commentCount: Int.random(in: 0...4),
                    timestamp: Date().addingTimeInterval(Double.random(in: -86400...0))
                )
                modelContext.insert(post)
            }
        }
    }

    private static func seedEvents(modelContext: ModelContext, userId: UUID, users: [(id: UUID, name: String, username: String)]) {
        let cal = Calendar.current
        let now = Date()

        let allComms = (try? modelContext.fetch(FetchDescriptor<Club>(predicate: #Predicate { $0.parentClubId == nil }))) ?? []
        guard !allComms.isEmpty else { return }

        // Prefer named clubs when they exist (rich seed), but fall back
        // to whatever top-level clubs the user's DB has so events are
        // never missing on older installs.
        func pick(_ name: String, fallback idx: Int) -> Club {
            if let match = allComms.first(where: { $0.name == name }) { return match }
            return allComms[idx % allComms.count]
        }
        let runClub = pick("Queen's Run Club", fallback: 0)
        let basketball = pick("Kingston Pickup Basketball", fallback: 1)
        let powerlifting = pick("Queen's Powerlifting", fallback: 2)
        let cycling = pick("Kingston Cycling Group", fallback: 3)
        let soccer = pick("Queen's Intramural Soccer", fallback: 4)

        // Helper: next occurrence of a weekday at a given hour
        func nextWeekday(_ weekday: Int, hour: Int, minute: Int = 0) -> Date {
            var comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear, .weekday], from: now)
            comps.weekday = weekday
            comps.hour = hour
            comps.minute = minute
            var target = cal.date(from: comps) ?? now
            if target <= now { target = cal.date(byAdding: .weekOfYear, value: 1, to: target) ?? target }
            return target
        }

        // Wednesday 5K Loop (Run Club, recurring weekly)
        let e1 = ClubEvent(
            clubId: runClub.id,
            creatorId: users[0].id,
            creatorName: users[0].name,
            title: "Wednesday 5K Loop",
            eventDescription: "Meet at the waterfront for a 5K group run. All paces welcome.",
            location: "Kingston Waterfront",
            date: nextWeekday(4, hour: 18),
            endDate: nextWeekday(4, hour: 19),
            maxAttendees: 30,
            attendeeIds: [userId, users[0].id, users[2].id, users[4].id],
            eventType: .groupRun,
            isRecurring: true,
            recurrenceRule: "weekly"
        )

        // Friday Night Hoops (Basketball, recurring weekly)
        let e2 = ClubEvent(
            clubId: basketball.id,
            creatorId: users[1].id,
            creatorName: users[1].name,
            title: "Friday Night Hoops",
            eventDescription: "Pickup basketball at the ARC. First 10 play, winners stay on.",
            location: "The ARC - Gymnasium",
            date: nextWeekday(6, hour: 19),
            endDate: nextWeekday(6, hour: 21),
            maxAttendees: 20,
            attendeeIds: [userId, users[1].id, users[3].id, users[5].id, users[7].id],
            eventType: .pickupGame,
            isRecurring: true,
            recurrenceRule: "weekly"
        )

        // Powerlifting Mock Meet
        let e3 = ClubEvent(
            clubId: powerlifting.id,
            creatorId: users[2].id,
            creatorName: users[2].name,
            title: "Powerlifting Mock Meet",
            eventDescription: "Squat, bench, deadlift. 3 attempts each. Friendly competition — all levels.",
            location: "The ARC - Platform Area",
            date: cal.date(byAdding: .day, value: 5, to: cal.startOfDay(for: now))!.addingTimeInterval(10 * 3600),
            endDate: cal.date(byAdding: .day, value: 5, to: cal.startOfDay(for: now))!.addingTimeInterval(14 * 3600),
            maxAttendees: 20,
            attendeeIds: [users[0].id, users[2].id, users[4].id, users[6].id, users[8].id],
            eventType: .competition
        )

        // Saturday Morning Ride (Cycling, recurring weekly)
        let e4 = ClubEvent(
            clubId: cycling.id,
            creatorId: users[3].id,
            creatorName: users[3].name,
            title: "Saturday Morning Ride",
            eventDescription: "50km road ride out to Gananoque and back. Moderate pace.",
            location: "Kingston City Hall",
            date: nextWeekday(7, hour: 7, minute: 30),
            endDate: nextWeekday(7, hour: 10),
            attendeeIds: [users[3].id, users[6].id],
            eventType: .groupRide,
            isRecurring: true,
            recurrenceRule: "weekly"
        )

        // Thursday Scrimmage (Soccer, recurring weekly)
        let e5 = ClubEvent(
            clubId: soccer.id,
            creatorId: users[5].id,
            creatorName: users[5].name,
            title: "Thursday Scrimmage",
            eventDescription: "Co-ed scrimmage on the turf field. Bring cleats.",
            location: "Queen's Turf Field",
            date: nextWeekday(5, hour: 18),
            endDate: nextWeekday(5, hour: 19, minute: 30),
            maxAttendees: 22,
            attendeeIds: [users[5].id, users[7].id, users[9].id],
            eventType: .scrimmage,
            isRecurring: true,
            recurrenceRule: "weekly"
        )

        // Past events
        let e6 = ClubEvent(
            clubId: runClub.id,
            creatorId: users[0].id,
            creatorName: users[0].name,
            title: "Sunrise 10K",
            eventDescription: "Early morning 10K along the waterfront trail.",
            location: "Kingston Waterfront",
            date: cal.date(byAdding: .day, value: -3, to: cal.startOfDay(for: now))!.addingTimeInterval(6 * 3600),
            endDate: cal.date(byAdding: .day, value: -3, to: cal.startOfDay(for: now))!.addingTimeInterval(7.5 * 3600),
            attendeeIds: [userId, users[0].id, users[2].id, users[4].id, users[6].id],
            eventType: .groupRun
        )

        let e7 = ClubEvent(
            clubId: basketball.id,
            creatorId: users[1].id,
            creatorName: users[1].name,
            title: "3v3 Tournament",
            eventDescription: "Single elimination 3v3 tournament. Prizes for winners.",
            location: "The ARC - Gymnasium",
            date: cal.date(byAdding: .day, value: -5, to: cal.startOfDay(for: now))!.addingTimeInterval(14 * 3600),
            attendeeIds: [users[1].id, users[3].id, users[5].id, users[7].id, users[9].id],
            eventType: .tournament
        )

        for event in [e1, e2, e3, e4, e5, e6, e7] {
            modelContext.insert(event)
        }
    }
}

// MARK: - Club Feed View (embedded in Feed tab)

enum ClubViewMode: String, CaseIterable {
    case list = "List"
    case map = "Map"
}

/// Lightweight sort for the Your Clubs rail. Optimizes the "I'm in a lot of
/// clubs and need to find the one I care about right now" flow.
enum YourClubsSort: String, CaseIterable, Identifiable {
    case recent, nearby, upNext, active
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recent: return "All"
        case .nearby: return "Nearby"
        case .upNext: return "Up next"
        case .active: return "Active"
        }
    }
    var icon: String {
        switch self {
        case .recent: return "square.grid.2x2"
        case .nearby: return "location.fill"
        case .upNext: return "calendar"
        case .active: return "bolt.fill"
        }
    }
}

enum DiscoverTab: String, CaseIterable, Identifiable {
    case forYou, nearby, friends, challenges
    var id: String { rawValue }
    var label: String {
        switch self {
        case .forYou: return "For You"
        case .nearby: return "Nearby"
        case .friends: return "Friends"
        case .challenges: return "Challenges"
        }
    }
    var icon: String {
        switch self {
        case .forYou: return "sparkles"
        case .nearby: return "location.fill"
        case .friends: return "person.2.fill"
        case .challenges: return "flag.checkered"
        }
    }
}

struct ClubFeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allClubs: [Club]
    @Query private var allClubPosts: [ClubPost]
    @Query private var allChallenges: [ClubChallenge]
    @Query private var allEvents: [ClubEvent]
    @Query private var presenceStates: [UserPresenceState]

    let profile: UserProfile

    @State private var showingCreateClub = false
    @State private var selectedClub: Club?
    @State private var selectedEvent: ClubEvent?
    @State private var selectedCategory: ClubCategory? = nil
    @State private var clubViewMode: ClubViewMode = .list
    @State private var searchText: String = ""
    @State private var selectedMapClub: Club? = nil
    @State private var yourClubsSort: YourClubsSort = .recent
    @State private var presentingSearch: Bool = false
    @State private var presentingMap: Bool = false
    @State private var discoverTab: DiscoverTab = .forYou
    @State private var showAllYourClubs: Bool = false
    @State private var showAllEvents: Bool = false

    // Demo "user location" — Kingston, ON. Replace with CoreLocation once
    // the real auth flow lands. Keeping the haversine helper lets us
    // compute meaningful distances for any seeded club coord.
    private let userLat: Double = 44.225
    private let userLon: Double = -76.490

    // MARK: - Computed Properties

    private var topLevelClubs: [Club] {
        allClubs.filter { $0.parentClubId == nil }
    }

    private var yourClubs: [Club] {
        topLevelClubs.filter { $0.memberIds.contains(profile.id) }
    }

    /// yourClubs reordered by the active sort + category filter. When
    /// a category chip is selected, only clubs in that category appear.
    private var sortedYourClubs: [Club] {
        let pool: [Club]
        if let cat = selectedCategory {
            pool = yourClubs.filter { $0.resolvedCategory == cat }
        } else {
            pool = yourClubs
        }
        switch yourClubsSort {
        case .recent:
            return pool.sorted { a, b in
                let la = liveCount(for: a), lb = liveCount(for: b)
                if la != lb { return la > lb }
                let ta = a.lastActivityDate ?? a.createdAt
                let tb = b.lastActivityDate ?? b.createdAt
                return ta > tb
            }
        case .nearby:
            return pool.sorted {
                let a = distanceKm(lat: $0.latitude ?? 90, lon: $0.longitude ?? 0)
                let b = distanceKm(lat: $1.latitude ?? 90, lon: $1.longitude ?? 0)
                return a < b
            }
        case .upNext:
            return pool.sorted { a, b in
                let da = nextEvent(for: a)?.date ?? .distantFuture
                let db = nextEvent(for: b)?.date ?? .distantFuture
                return da < db
            }
        case .active:
            return pool.sorted { liveCount(for: $0) > liveCount(for: $1) }
        }
    }

    private var recommendedClubs: [Club] {
        topLevelClubs.filter { !$0.memberIds.contains(profile.id) }
    }

    private var activeCategories: [ClubCategory] {
        let cats = Set(topLevelClubs.map { $0.resolvedCategory })
        return ClubCategory.allCases.filter { cats.contains($0) }
    }

    private func matchesSearch(_ club: Club) -> Bool {
        guard !searchText.isEmpty else { return true }
        let q = searchText.lowercased()
        return club.name.lowercased().contains(q)
            || (club.location?.lowercased().contains(q) ?? false)
            || club.resolvedCategory.rawValue.lowercased().contains(q)
    }

    private var searchFilteredYourClubs: [Club] {
        let clubs = yourClubs.filter { matchesSearch($0) }
        if let cat = selectedCategory {
            return clubs.filter { $0.resolvedCategory == cat }
        }
        return clubs
    }

    private var searchFilteredRecommended: [Club] {
        let clubs = recommendedClubs.filter { matchesSearch($0) }
        let filtered = selectedCategory == nil ? clubs : clubs.filter { $0.resolvedCategory == selectedCategory }
        // Sort by distance (when coordinates exist) then by member count —
        // nearest + largest first so Discover leads with the strongest picks.
        return filtered.sorted { a, b in
            let da: Double = {
                guard let la = a.latitude, let lo = a.longitude else { return .infinity }
                return distanceKm(lat: la, lon: lo)
            }()
            let db: Double = {
                guard let la = b.latitude, let lo = b.longitude else { return .infinity }
                return distanceKm(lat: la, lon: lo)
            }()
            if da != db { return da < db }
            return a.memberCount > b.memberCount
        }
    }

    private var featuredChallenge: ClubChallenge? {
        let myClubIds = Set(yourClubs.map(\.id))
        return allChallenges.first { myClubIds.contains($0.clubId) && $0.isActive }
    }

    private var allVisibleClubs: [Club] {
        topLevelClubs.filter { matchesSearch($0) }
    }

    private var clubsWithCoordinates: [Club] {
        let filtered = selectedCategory == nil ? allVisibleClubs : allVisibleClubs.filter { $0.resolvedCategory == selectedCategory }
        return filtered.filter { $0.latitude != nil && $0.longitude != nil }
    }

    // MARK: - Local + events helpers

    /// Every upcoming event, sorted soonest first. Drives the main
    /// events block — broad pool so the section has content even when
    /// the user's clubs are quiet and the recommended pool is small.
    private var upcomingEvents: [ClubEvent] {
        let now = Date()
        return allEvents
            .filter { $0.date > now }
            .sorted { $0.date < $1.date }
    }

    /// "Recommended" events — upcoming events from clubs the user is
    /// NOT in, that are (a) hosted by a public/open club and (b) match
    /// one of the user's category interests. Drives the FOR YOU badge
    /// mixed into the Upcoming Events list so discovery happens where
    /// users are already browsing.
    private var recommendedEvents: [ClubEvent] {
        let now = Date()
        let myClubIds = Set(yourClubs.map(\.id))
        let myCats = Set(yourClubs.map(\.resolvedCategory))
        return allEvents
            .filter { e in
                guard e.date > now, !myClubIds.contains(e.clubId) else { return false }
                guard let club = allClubs.first(where: { $0.id == e.clubId }) else { return false }
                // Only public clubs (private clubs should remain invite/
                // request-scoped — don't leak their events to strangers).
                guard club.isOpen else { return false }
                // Interest match: same category as a club the user is in,
                // OR user is in no clubs yet (cold-start discoverability).
                return myCats.isEmpty || myCats.contains(club.resolvedCategory)
            }
            .sorted { $0.date < $1.date }
    }

    /// Names of the user's friends who are attending a given event.
    /// Used for the "Priya + 2 friends going" social-proof line.
    private func friendsGoingNames(_ event: ClubEvent) -> [String] {
        let followedIds = Set(SocialSeeder.fakeUsers.prefix(5).map(\.id))
        let matches = event.attendeeIds.filter { followedIds.contains($0) }
        return matches.compactMap { id in
            SocialSeeder.fakeUsers.first(where: { $0.id == id })?.name
                .components(separatedBy: " ").first
        }
    }

    /// Upcoming events only in clubs the user is a member of.
    /// Drives the "IN YOUR CLUBS" events rail — prioritized at the top.
    private var upcomingEventsInMyClubs: [ClubEvent] {
        let now = Date()
        let myIds = Set(yourClubs.map(\.id))
        return allEvents
            .filter { $0.date > now && myIds.contains($0.clubId) }
            .sorted { $0.date < $1.date }
    }

    /// Upcoming events in clubs the user has NOT joined yet (discovery).
    /// Pulls from ALL non-joined clubs (not just the recommended shortlist)
    /// so the Events block has something to render even when the user's
    /// own clubs are quiet.
    private var upcomingEventsNearby: [ClubEvent] {
        let now = Date()
        let myIds = Set(yourClubs.map(\.id))
        return allEvents
            .filter { $0.date > now && !myIds.contains($0.clubId) }
            .sorted { $0.date < $1.date }
    }

    /// Members of the user's clubs who are currently training.
    /// Drives the ACTIVE NOW horizontal avatar rail under Your Clubs.
    private var activeMembersInMyClubs: [(userId: UUID, name: String, workoutType: String?, clubName: String)] {
        let myClubMemberships = yourClubs.flatMap { club in
            club.memberIds.filter { $0 != profile.id }.map { ($0, club.name) }
        }
        // A user can be in multiple of the viewer's clubs — keep the first
        // club name we see per user. `uniqueKeysWithValues` would trap.
        let byUser = Dictionary(myClubMemberships.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
        return presenceStates
            .filter { $0.status == .training && byUser[$0.userId] != nil }
            .compactMap { state in
                guard let clubName = byUser[state.userId] else { return nil }
                let name = SocialSeeder.fakeUsers.first(where: { $0.id == state.userId })?.name
                    ?? "Member"
                return (state.userId, name, state.workoutTypeRaw, clubName)
            }
    }

    /// Next upcoming event for a given club (or nil).
    private func nextEvent(for club: Club) -> ClubEvent? {
        let now = Date()
        return allEvents
            .filter { $0.clubId == club.id && $0.date > now }
            .min(by: { $0.date < $1.date })
    }

    /// Haversine distance in km from demo user location to a coord.
    private func distanceKm(lat: Double, lon: Double) -> Double {
        let r = 6371.0
        let dLat = (lat - userLat) * .pi / 180
        let dLon = (lon - userLon) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(userLat * .pi / 180) * cos(lat * .pi / 180)
              * sin(dLon / 2) * sin(dLon / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Formatted "2.1 mi" / "under 1 mi" / "ft" string. Falls back to nil
    /// when the club has no coordinates.
    private func distanceString(for club: Club) -> String? {
        guard let lat = club.latitude, let lon = club.longitude else { return nil }
        let km = distanceKm(lat: lat, lon: lon)
        let mi = km * 0.6213711922
        if mi < 0.1 { return "here" }
        if mi < 1 { return String(format: "%.1f mi", mi) }
        return "\(Int(mi.rounded())) mi"
    }

    /// How many of this club's members are currently training (live).
    private func liveCount(for club: Club) -> Int {
        let ids = Set(club.memberIds)
        return presenceStates.filter { ids.contains($0.userId) && $0.status == .training }.count
    }

    /// Does this club have an event scheduled for today?
    private func hasEventToday(_ club: Club) -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return false }
        return allEvents.contains { $0.clubId == club.id && $0.date >= today && $0.date < tomorrow }
    }

    /// How many of the user's followed friends are members of this club.
    /// Drives the "Marcus + 2 friends are in" chip on recommended rows.
    private func friendsInClub(_ club: Club) -> Int {
        // Since we don't have explicit Friend-graph access here yet, use
        // SocialSeeder's fakeUsers as a demo stand-in for "people I follow".
        let followedIds = Set(SocialSeeder.fakeUsers.prefix(5).map(\.id))
        return club.memberIds.filter { followedIds.contains($0) }.count
    }

    private func firstFriendNameInClub(_ club: Club) -> String? {
        let followedIds = Set(SocialSeeder.fakeUsers.prefix(5).map(\.id))
        if let match = club.memberIds.first(where: { followedIds.contains($0) }) {
            return SocialSeeder.fakeUsers.first(where: { $0.id == match })?.name
                .components(separatedBy: " ").first
        }
        return nil
    }

    @ViewBuilder
    private func yourClubAvatar(_ club: Club) -> some View {
        let live = liveCount(for: club)
        let eventToday = hasEventToday(club)

        ZStack {
            clubAvatar(club, size: 60)

            // Activity badges: green = live members, amber = event today.
            // Max one visible at a time (live wins) to keep the shelf clean.
            if live > 0 {
                Circle()
                    .fill(GQColors.success)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(GQColors.background, lineWidth: 2))
                    .frame(width: 60, height: 60, alignment: .bottomTrailing)
            } else if eventToday {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Image(systemName: "calendar")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .overlay(Circle().stroke(GQColors.background, lineWidth: 2))
                    .frame(width: 60, height: 60, alignment: .bottomTrailing)
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Search + category chips pinned at the top. Mirrors the
                // Discover page: bar is a tappable button that opens the
                // full search sheet.
                searchAndCategoryStrip
                    .padding(.top, 4)

                // Apple Settings-style inset groups: each section has
                // its header outside the card, rows inside a white
                // rounded card. Sections hide when the active
                // category filter leaves them empty.
                if !sortedYourClubs.isEmpty {
                    groupedSection(header: "YOUR CLUBS") {
                        yourClubsRowsOnly
                    }
                    .padding(.top, 12)
                }

                if !computedEventRows.isEmpty {
                    groupedSection(header: "UPCOMING EVENTS") {
                        eventsRowsOnly
                    }
                    .padding(.top, 20)
                }

                if hasAnyDiscoverContent {
                    groupedSection(header: "DISCOVER") {
                        discoverCardContent
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                }

                // When an active filter hides everything, show a
                // friendly nudge with a one-tap clear.
                if selectedCategory != nil
                    && sortedYourClubs.isEmpty
                    && computedEventRows.isEmpty
                    && !hasAnyDiscoverContent {
                    filterEmptyStateBlock
                        .padding(.top, 40)
                }

                if yourClubs.isEmpty && searchFilteredRecommended.isEmpty {
                    emptyStateBlock
                        .padding(.top, 40)
                }

                Spacer(minLength: 60)
            }
        }
        .scrollContentBackground(.hidden)
        .background(GQColors.background.ignoresSafeArea())
        .navigationTitle("Clubs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button { presentingSearch = true } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(GQColors.textPrimary)
                    }
                    Button { showingCreateClub = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(GQGradients.primary)
                    }
                }
            }
        }
        .refreshable {
            try? await Task.sleep(for: .milliseconds(300))
        }
        .onAppear {
            ClubSeeder.seedIfNeeded(modelContext: modelContext, userId: profile.id)
            try? ClubService.shared.evaluateClubHealth()
        }
        .sheet(isPresented: $showingCreateClub) {
            CreateClubSheet(profile: profile)
        }
        .sheet(item: $selectedClub) { club in
            ClubDetailView(club: club, profile: profile)
        }
        .sheet(isPresented: $presentingSearch) {
            clubSearchSheet
        }
        .sheet(isPresented: $presentingMap) {
            clubMapSheet
        }
        .sheet(item: $selectedEvent) { event in
            if let club = allClubs.first(where: { $0.id == event.clubId }) {
                ClubDetailView(club: club, profile: profile)
            }
        }
    }

    /// Hairline between sections — edge-to-edge, matches Apple List
    /// section separators.
    private var rowDivider: some View {
        Rectangle()
            .fill(GQColors.borderDefault)
            .frame(height: 0.5)
            .padding(.horizontal, 16)
    }

    /// Hairline between rows *within* a section — inset past the
    /// avatar so it looks like a grouped-list separator instead of a
    /// full-width section break.
    private var inRowDivider: some View {
        Rectangle()
            .fill(GQColors.borderDefault.opacity(0.7))
            .frame(height: 0.5)
            .padding(.leading, 74)
            .padding(.trailing, 16)
    }

    /// Apple Settings-style section — tracked-caps header at 32pt
    /// from the screen edge, content inside a white rounded card below.
    @ViewBuilder
    private func groupedSection<Content: View>(
        header: String,
        headerAccessory: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(header)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(GQColors.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)

            if let headerAccessory {
                headerAccessory
            }

            content()
                .groupedCard()
        }
    }

    // MARK: - Search + categories strip (top of page)

    /// Top filter strip — horizontal row of category chips under the
    /// nav. A trailing Map chip replaces the old toolbar map icon so
    /// the nav stays at two icons (search + create).
    @ViewBuilder
    private var searchAndCategoryStrip: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    categoryChip(nil, label: "All")
                    ForEach(browseCategories, id: \.self) { cat in
                        categoryChip(cat, label: cat.rawValue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()

            Button {
                #if canImport(UIKit)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
                presentingMap = true
            } label: {
                Image(systemName: "map")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textSecondary)
                    .frame(width: 34, height: 30)
                    .background(
                        Capsule().fill(GQColors.surfaceBase)
                    )
                    .overlay(
                        Capsule().stroke(GQColors.borderDefault.opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func categoryChip(_ cat: ClubCategory?, label: String) -> some View {
        let selected = (cat == nil && selectedCategory == nil) || (cat != nil && selectedCategory == cat)
        Button {
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                selectedCategory = selected ? nil : cat
            }
        } label: {
            HStack(spacing: 4) {
                if let cat {
                    Image(systemName: cat.icon)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(selected ? .white : GQColors.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(selected
                    ? AnyShapeStyle(GQGradients.primary)
                    : AnyShapeStyle(GQColors.surfaceBase))
            )
            .overlay(
                Capsule().stroke(
                    selected ? Color.clear : GQColors.borderDefault.opacity(0.5),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Popular this week (horizontal featured rail)

    /// Horizontal rail of the top clubs by member count — gives the
    /// page a browseable, visual hook. Renders as a single full-width
    /// hero card when only one club qualifies so the section never
    /// feels half-empty.
    @ViewBuilder
    private var popularThisWeekRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeaderLabel(
                "POPULAR THIS WEEK",
                trailing: featuredClubs.count > 1 ? "\(featuredClubs.count)" : nil
            )

            if featuredClubs.count == 1, let solo = featuredClubs.first {
                Button { selectedClub = solo } label: {
                    featuredHeroCard(solo)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(featuredClubs) { club in
                            Button { selectedClub = club } label: {
                                featuredCard(club)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    /// Full-width hero variant of the featured card — bounded 190pt
    /// height, photo clipped, overlay shows category + FEATURED tag on
    /// top and name + distance + members + Open CTA on bottom.
    @ViewBuilder
    private func featuredHeroCard(_ club: Club) -> some View {
        let cat = club.resolvedCategory
        let isMember = club.memberIds.contains(profile.id)
        ZStack(alignment: .bottomLeading) {
            ClubCoverImage(club: club, fallbackGradient: GQGradients.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.35), .black.opacity(0.1), .black.opacity(0.78)],
                startPoint: .top, endPoint: .bottom
            )

            // Top row — category + FEATURED
            VStack {
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: cat.icon)
                            .font(.system(size: 10, weight: .bold))
                        Text(cat.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.ultraThinMaterial))

                    Spacer()

                    Text("FEATURED")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(GQGradients.primary))
                }
                Spacer(minLength: 0)
            }
            .padding(12)

            // Bottom — name, meta row, Open CTA
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text(club.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if club.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.95))
                        }
                    }
                    HStack(spacing: 8) {
                        if let loc = club.location, !loc.isEmpty {
                            Label(loc, systemImage: "mappin")
                                .lineLimit(1)
                        }
                        Label("\(club.memberCount)", systemImage: "person.2.fill")
                        if let dist = distanceString(for: club) {
                            Label(dist, systemImage: "location.fill")
                        }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .labelStyle(CompactMetaLabelStyle())
                }

                Spacer(minLength: 0)

                Text(isMember ? "Open" : "View")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(GQColors.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(.white))
            }
            .padding(12)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
    }

    // MARK: - Map sheet

    /// Full-screen map sheet — reuses `mapModeContent` so clubs and
    /// events show as pins. Recenter + filter chips at the top.
    @ViewBuilder
    private var clubMapSheet: some View {
        NavigationStack {
            ClubMapView(
                clubs: topLevelClubs,
                events: allEvents.filter { $0.date > Date() },
                profile: profile,
                selectedClub: { club in
                    presentingMap = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        selectedClub = club
                    }
                },
                selectedEvent: { event in
                    presentingMap = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if let club = allClubs.first(where: { $0.id == event.clubId }) {
                            selectedClub = club
                        }
                    }
                }
            )
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { presentingMap = false }
                        .foregroundColor(GQColors.textPrimary)
                }
            }
        }
    }

    /// Your clubs — rich vertical list with a live status line under each
    /// club name. Replaces the old horizontal avatar shelf. Each row shows
    /// what's actually happening right now in that specific club (live
    /// members, event today, next event, or fallback) so the user can
    /// scan the list and pick the one worth opening.
    /// Rows-only variant for use inside a groupedSection card.
    /// Trims to the first 5 clubs until the user taps "Show all" so
    /// the card stays scannable at 100+ clubs.
    @ViewBuilder
    private var yourClubsRowsOnly: some View {
        let collapsedLimit = 5
        let total = sortedYourClubs.count
        let visible = showAllYourClubs ? sortedYourClubs : Array(sortedYourClubs.prefix(collapsedLimit))

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { idx, club in
                Button { selectedClub = club } label: {
                    yourClubRow(club)
                }
                .buttonStyle(.plain)

                if idx < visible.count - 1 {
                    inRowDivider
                }
            }

            if total > collapsedLimit {
                inRowDivider
                showAllRow(
                    label: showAllYourClubs ? "Show fewer" : "Show all \(total) clubs",
                    icon: showAllYourClubs ? "chevron.up" : "chevron.down"
                ) {
                    #if canImport(UIKit)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAllYourClubs.toggle()
                    }
                }
            }
        }
    }

    /// Collapse/expand row used at the bottom of capped lists —
    /// small, centered, subtle (Apple-style footer link).
    @ViewBuilder
    private func showAllRow(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(GQGradients.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var yourClubsListBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeaderLabel("YOUR CLUBS")
            yourClubsRowsOnly
        }
    }

    /// One rich club row — matches the Friends post-card spacing
    /// language (avatar + two-line content + trailing status).
    @ViewBuilder
    private func yourClubRow(_ club: Club) -> some View {
        let live = liveCount(for: club)
        let eventToday = hasEventToday(club)

        HStack(spacing: 12) {
            clubAvatar(club, size: 46)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(club.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    if club.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(GQGradients.primary)
                    }
                    if !club.isOpen {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(GQColors.textTertiary)
                    }
                }
                yourClubSubtitleText(club, live: live, eventToday: eventToday)
            }

            Spacer(minLength: 8)

            yourClubTrailing(club, live: live, eventToday: eventToday)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// Live > event today > next event > friends > members, in that
    /// priority order. One subtitle line keeps the row scannable.
    @ViewBuilder
    private func yourClubSubtitleText(_ club: Club, live: Int, eventToday: Bool) -> some View {
        if live > 0 {
            HStack(spacing: 5) {
                Circle().fill(GQColors.success).frame(width: 6, height: 6)
                Text("\(live) training now")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(GQColors.success)
            }
        } else if eventToday, let ev = nextEvent(for: club), Calendar.current.isDateInToday(ev.date) {
            Text("Today · \(ev.date.formatted(date: .omitted, time: .shortened)) — \(ev.title)")
                .font(.system(size: 12))
                .foregroundColor(GQColors.textSecondary)
                .lineLimit(1)
        } else if let ev = nextEvent(for: club) {
            Text("\(eventDayLabelShort(ev.date)) · \(ev.title)")
                .font(.system(size: 12))
                .foregroundColor(GQColors.textTertiary)
                .lineLimit(1)
        } else {
            let friends = friendsInClub(club)
            if friends > 0, let firstName = firstFriendNameInClub(club) {
                Text(friends == 1 ? "\(firstName) is in" : "\(firstName) + \(friends - 1) friends")
                    .font(.system(size: 12))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)
            } else {
                Text("\(club.memberCount == 1 ? "1 member" : "\(club.memberCount) members") · \(club.resolvedCategory.rawValue)")
                    .font(.system(size: 12))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    /// Trailing badge: live pill (green), today pill (amber), or chevron.
    @ViewBuilder
    private func yourClubTrailing(_ club: Club, live: Int, eventToday: Bool) -> some View {
        if live > 0 {
            Text("\(live) LIVE")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(GQColors.success))
        } else if eventToday {
            Text("TODAY")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.4)
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.orange))
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(GQColors.textTertiary)
        }
    }

    /// Short date label for the clubs list — "Today", "Tomorrow",
    /// "Tue", or "Apr 28".
    private func eventDayLabelShort(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        let soon = cal.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = date < soon ? "EEE" : "MMM d"
        return fmt.string(from: date)
    }

    /// Reusable section header (uppercase label + right-aligned meta).
    private func sectionHeaderLabel(_ title: String, trailing: String? = nil) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.0)
                .foregroundColor(GQColors.textTertiary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    /// Pre-computed ordered rows for the events section — separates the
    /// non-View logic out of the @ViewBuilder body so we can use
    /// imperative control flow (prefix + de-dup + mapping). Applies
    /// the selected category chip to filter events by their parent
    /// club's category.
    private var computedEventRows: [(event: ClubEvent, joined: Bool, recommended: Bool)] {
        let categoryFilter: (ClubEvent) -> Bool = { [selectedCategory] event in
            guard let cat = selectedCategory else { return true }
            return allClubs.first(where: { $0.id == event.clubId })?.resolvedCategory == cat
        }

        let myEvents = Array(upcomingEventsInMyClubs.filter(categoryFilter).prefix(3))
        var seen = Set(myEvents.map(\.id))
        let recEvents = Array(recommendedEvents
            .filter { !seen.contains($0.id) && categoryFilter($0) }
            .prefix(2))
        for r in recEvents { seen.insert(r.id) }
        let remainingBudget = max(0, 6 - myEvents.count - recEvents.count)
        let otherEvents = Array(upcomingEvents
            .filter { !seen.contains($0.id) && categoryFilter($0) }
            .prefix(remainingBudget))

        let myClubIdSet = Set(yourClubs.map(\.id))
        return myEvents.map { ($0, true, false) }
            + recEvents.map { ($0, false, true) }
            + otherEvents.map { ($0, myClubIdSet.contains($0.clubId), false) }
    }

    /// Events feed — in-your-clubs events first, then FOR-YOU
    /// recommendations from matching public clubs, then any other
    /// upcoming event. Rows are hairline-separated for a continuous
    /// list.
    @ViewBuilder
    private var eventsRowsOnly: some View {
        let allRows = computedEventRows
        let collapsedLimit = 4
        let total = allRows.count
        let rows = showAllEvents ? allRows : Array(allRows.prefix(collapsedLimit))

        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.event.id) { idx, item in
                Button { selectedEvent = item.event } label: {
                    eventRow(item.event, isJoinedClub: item.joined, recommended: item.recommended)
                }
                .buttonStyle(.plain)
                if idx < rows.count - 1 {
                    inRowDivider
                }
            }

            if total > collapsedLimit {
                inRowDivider
                showAllRow(
                    label: showAllEvents ? "Show fewer" : "Show all \(total) events",
                    icon: showAllEvents ? "chevron.up" : "chevron.down"
                ) {
                    #if canImport(UIKit)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showAllEvents.toggle()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var eventsBlock: some View {
        let rows = computedEventRows

        VStack(alignment: .leading, spacing: 0) {
            sectionHeaderLabel("UPCOMING EVENTS")

            ForEach(Array(rows.enumerated()), id: \.element.event.id) { idx, item in
                Button { selectedEvent = item.event } label: {
                    eventRow(item.event, isJoinedClub: item.joined, recommended: item.recommended)
                }
                .buttonStyle(.plain)

                if idx < rows.count - 1 {
                    rowDivider
                }
            }
        }
    }

    /// One event row — date tile + title + club name + meta + friend
    /// social-proof line. Shows a "FOR YOU" badge when this is a
    /// recommendation from a club the user hasn't joined.
    private func eventRow(_ event: ClubEvent, isJoinedClub: Bool, recommended: Bool = false) -> some View {
        let club = allClubs.first { $0.id == event.clubId }
        let isGoing = event.attendeeIds.contains(profile.id)
        let friends = friendsGoingNames(event)

        return HStack(spacing: 12) {
            eventDateTile(event.date, accent: recommended ? Color.orange : nil)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    if recommended {
                        Text("FOR YOU")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(GQGradients.primary))
                    }
                }
                Text(eventSubtitle(event, isJoinedClub: isJoinedClub))
                    .font(.system(size: 12))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Label(event.date.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(GQColors.textSecondary)
                        .labelStyle(CompactMetaLabelStyle())
                    if let loc = event.location ?? club?.location, !loc.isEmpty {
                        Label(loc, systemImage: "mappin")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(GQColors.textSecondary)
                            .lineLimit(1)
                            .labelStyle(CompactMetaLabelStyle())
                    }
                }
                // Friend social-proof line — strongest signal for
                // turning an event row into a "let's go" moment.
                if !friends.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text(friendsGoingLabel(friends: friends, total: event.attendeeIds.count))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(GQGradients.primary)
                    .padding(.top, 1)
                }
            }

            Spacer(minLength: 8)

            if isGoing {
                Text("GOING")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(GQGradients.primary))
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(event.attendeeIds.count)")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(GQColors.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func friendsGoingLabel(friends: [String], total: Int) -> String {
        switch friends.count {
        case 1: return "\(friends[0]) going"
        case 2: return "\(friends[0]) + \(friends[1]) going"
        default: return "\(friends[0]) + \(friends.count - 1) friends going"
        }
    }

    /// Calendar-style date tile — month label on top, day number below.
    /// `accent` overrides the header color (used for the FOR YOU orange
    /// stripe on recommended-event rows).
    private func eventDateTile(_ date: Date, accent: Color? = nil) -> some View {
        let cal = Calendar.current
        let monthFmt = DateFormatter()
        monthFmt.dateFormat = "MMM"
        let month = monthFmt.string(from: date).uppercased()
        let day = "\(cal.component(.day, from: date))"

        return VStack(spacing: 0) {
            Text(month)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(
                    Group {
                        if let accent { accent }
                        else { GQGradients.primary }
                    }
                )
            Text(day)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(GQColors.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 44, height: 44)
        .background(GQColors.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(GQColors.borderDefault.opacity(0.6), lineWidth: 0.5)
        )
    }

    private func eventSubtitle(_ event: ClubEvent, isJoinedClub: Bool) -> String {
        let clubName = allClubs.first { $0.id == event.clubId }?.name ?? "Club"
        if isJoinedClub {
            return clubName
        }
        let club = allClubs.first { $0.id == event.clubId }
        if let loc = club?.location, !loc.isEmpty { return "\(clubName) · \(loc)" }
        return clubName
    }

    /// Discover pool — nearest non-joined clubs. Category chip filter
    /// from `searchFilteredRecommended` is already applied.
    private var discoverClubs: [Club] {
        searchFilteredRecommended
    }

    // MARK: - Discover tab data

    /// Clubs where the user has 1+ friends but isn't a member — highest
    /// social-proof signal for joining.
    private var friendsDiscoverClubs: [Club] {
        searchFilteredRecommended.filter { friendsInClub($0) > 0 }
    }

    /// "For You" picks — a mix of friends'-clubs, nearby-with-location,
    /// and highest-member clubs, each paired with a human-readable
    /// reason. De-duplicates while preserving the order we'd like to
    /// feature them.
    private var forYouPicks: [(club: Club, reason: String)] {
        var out: [(Club, String)] = []
        var seen = Set<UUID>()

        // 1. Friends' clubs first — strongest social pull
        for club in friendsDiscoverClubs where !seen.contains(club.id) {
            let friends = friendsInClub(club)
            let name = firstFriendNameInClub(club) ?? "A friend"
            let reason = friends == 1 ? "\(name) is in" : "\(name) + \(friends - 1) friends"
            out.append((club, reason))
            seen.insert(club.id)
            if out.count >= 2 { break }
        }

        // 2. Category match — "because you lift", "because you run"
        let myCats = Set(yourClubs.map(\.resolvedCategory))
        for club in searchFilteredRecommended where !seen.contains(club.id) {
            if myCats.contains(club.resolvedCategory) {
                out.append((club, "Because you \(club.resolvedCategory.rawValue.lowercased())"))
                seen.insert(club.id)
                if out.count >= 4 { break }
            }
        }

        // 3. Top-by-members fallback
        let bySize = searchFilteredRecommended.sorted { $0.memberCount > $1.memberCount }
        for club in bySize where !seen.contains(club.id) {
            let reason = club.memberCount == 1 ? "1 member" : "\(club.memberCount) members"
            out.append((club, reason))
            seen.insert(club.id)
            if out.count >= 5 { break }
        }

        return out
    }

    /// Active challenges in clubs the user is NOT already in — the
    /// "Challenges" tab pitches these as joinable.
    private var joinableChallenges: [ClubChallenge] {
        let myClubIds = Set(yourClubs.map(\.id))
        return allChallenges
            .filter { $0.isActive && !myClubIds.contains($0.clubId) }
            .sorted { $0.endDate < $1.endDate }
    }

    /// Active challenges in clubs the user IS in — surfaced alongside
    /// joinable ones so there's always content in the challenges tab.
    private var myActiveChallenges: [ClubChallenge] {
        let myClubIds = Set(yourClubs.map(\.id))
        return allChallenges
            .filter { $0.isActive && myClubIds.contains($0.clubId) }
            .sorted { $0.endDate < $1.endDate }
    }

    private var hasAnyDiscoverContent: Bool {
        !searchFilteredRecommended.isEmpty
            || !myActiveChallenges.isEmpty
            || !joinableChallenges.isEmpty
    }

    /// Discover block — clubs you haven't joined yet, sorted nearest
    /// first. Same monogram + two-line row language as Your Clubs so
    /// the page reads as one list.
    @ViewBuilder
    private var discoverBlock: some View {
        let rows = Array(discoverClubs.prefix(8))
        VStack(alignment: .leading, spacing: 0) {
            sectionHeaderLabel("CLUBS NEAR YOU")

            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, club in
                Button { selectedClub = club } label: {
                    discoverClubRow(club)
                }
                .buttonStyle(.plain)

                if idx < rows.count - 1 {
                    rowDivider
                }
            }
        }
    }

    private func discoverClubRow(_ club: Club) -> some View {
        HStack(spacing: 12) {
            clubAvatar(club, size: 46)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(club.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    if club.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(GQGradients.primary)
                    }
                    if !club.isOpen {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(GQColors.textTertiary)
                    }
                }
                Text(discoverSubtitle(club))
                    .font(.system(size: 12))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let dist = distanceString(for: club) {
                Text(dist)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(GQColors.textSecondary)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// Prioritize what makes this club worth opening:
    /// friends-in > location > category + member count.
    private func discoverSubtitle(_ club: Club) -> String {
        let friends = friendsInClub(club)
        if friends > 0, let firstName = firstFriendNameInClub(club) {
            return friends == 1 ? "\(firstName) is in · \(club.memberCount) members"
                                : "\(firstName) + \(friends - 1) friends · \(club.memberCount) members"
        }
        if let loc = club.location, !loc.isEmpty {
            return "\(club.resolvedCategory.rawValue) · \(loc)"
        }
        return "\(club.resolvedCategory.rawValue) · \(club.memberCount) members"
    }

    // MARK: - Discover section (tabbed)

    /// Unified Discover section — one header + a segmented pill control
    /// that flips between "For You", "Nearby", "Friends", and
    /// "Challenges" tabs. Keeps the page scannable while still balancing
    /// personal vs. exploratory discovery.
    /// Content of the Discover card: segmented tab control at the top,
    /// hairline, then the active tab's body. Putting the control
    /// inside the card tightens the relationship between tabs and
    /// their content.
    @ViewBuilder
    private var discoverCardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            discoverSegmentedControl
                .padding(.vertical, 8)

            Rectangle()
                .fill(GQColors.borderDefault.opacity(0.5))
                .frame(height: 0.5)

            Group {
                switch discoverTab {
                case .forYou: forYouTabContent
                case .nearby: nearbyTabContent
                case .friends: friendsTabContent
                case .challenges: challengesTabContent
                }
            }
            .padding(.vertical, 8)
            .animation(.easeInOut(duration: 0.18), value: discoverTab)
        }
    }

    /// Just the per-tab content, without the outer "DISCOVER" header
    /// or segmented control — kept for any external caller that wants
    /// a bare-content variant.
    @ViewBuilder
    private var discoverTabsContentOnly: some View {
        Group {
            switch discoverTab {
            case .forYou: forYouTabContent
            case .nearby: nearbyTabContent
            case .friends: friendsTabContent
            case .challenges: challengesTabContent
            }
        }
        .animation(.easeInOut(duration: 0.18), value: discoverTab)
    }

    @ViewBuilder
    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DISCOVER")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundColor(GQColors.textTertiary)
                Spacer()
            }
            .padding(.horizontal, 16)

            discoverSegmentedControl

            Group {
                switch discoverTab {
                case .forYou: forYouTabContent
                case .nearby: nearbyTabContent
                case .friends: friendsTabContent
                case .challenges: challengesTabContent
                }
            }
            .animation(.easeInOut(duration: 0.18), value: discoverTab)
        }
    }

    @ViewBuilder
    private var discoverSegmentedControl: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(DiscoverTab.allCases) { tab in
                    discoverTabChip(tab)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func discoverTabChip(_ tab: DiscoverTab) -> some View {
        let selected = discoverTab == tab
        Button {
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                discoverTab = tab
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .symbolEffect(.bounce, value: selected)
                Text(tab.label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(selected ? .white : GQColors.textSecondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(selected
                    ? AnyShapeStyle(GQGradients.primary)
                    : AnyShapeStyle(GQColors.surfaceBase))
            )
            .overlay(
                Capsule().stroke(
                    selected ? Color.clear : GQColors.borderDefault.opacity(0.5),
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - For You tab

    @ViewBuilder
    private var forYouTabContent: some View {
        if forYouPicks.isEmpty {
            emptyDiscoverState(icon: "sparkles", title: "Nothing new yet", subtitle: "Join a club to unlock personalized picks.")
        } else {
            VStack(spacing: 10) {
                ForEach(Array(forYouPicks.prefix(4).enumerated()), id: \.element.club.id) { _, pick in
                    Button { selectedClub = pick.club } label: {
                        forYouHeroCard(pick.club, reason: pick.reason)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    /// Full-width For You card. `.overlay(alignment:)` keeps the text
    /// layers reliably pinned to the image regardless of ZStack
    /// ambiguity.
    @ViewBuilder
    private func forYouHeroCard(_ club: Club, reason: String) -> some View {
        let cat = club.resolvedCategory
        let isMember = club.memberIds.contains(profile.id)
        ClubCoverImage(club: club, fallbackGradient: GQGradients.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 170)
            .clipped()
            .overlay(
                LinearGradient(
                    colors: [.black.opacity(0.35), .black.opacity(0.08), .black.opacity(0.80)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(alignment: .topLeading) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                    Text(reason)
                        .font(.system(size: 10, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(.ultraThinMaterial))
                .padding(12)
            }
            .overlay(alignment: .bottomLeading) {
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(club.name)
                                .font(.system(size: 19, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if club.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.95))
                            }
                        }
                        HStack(spacing: 8) {
                            Label(cat.rawValue, systemImage: cat.icon)
                            if let loc = club.location, !loc.isEmpty {
                                Label(loc, systemImage: "mappin").lineLimit(1)
                            } else {
                                Label("\(club.memberCount)", systemImage: "person.2.fill")
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.92))
                        .labelStyle(CompactMetaLabelStyle())
                    }
                    Spacer(minLength: 0)
                    Text(isMember ? "Open" : "View")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(GQColors.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(.white))
                }
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// For You card — 240x180 cover with a reason chip up top so users
    /// always understand *why* we're showing them this club.
    @ViewBuilder
    private func forYouCard(_ club: Club, reason: String) -> some View {
        let cat = club.resolvedCategory
        ZStack(alignment: .bottomLeading) {
            ClubCoverImage(club: club, fallbackGradient: GQGradients.primary)
                .frame(width: 240, height: 180)
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.15), .black.opacity(0.72)],
                startPoint: .top, endPoint: .bottom
            )

            VStack {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .bold))
                        Text(reason)
                            .font(.system(size: 10, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.ultraThinMaterial))
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
            }
            .padding(10)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(club.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if club.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.95))
                    }
                }
                HStack(spacing: 8) {
                    Label(cat.rawValue, systemImage: cat.icon)
                        .lineLimit(1)
                    if let dist = distanceString(for: club) {
                        Label(dist, systemImage: "mappin")
                    } else {
                        Label("\(club.memberCount)", systemImage: "person.2.fill")
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.92))
                .labelStyle(CompactMetaLabelStyle())
            }
            .padding(12)
        }
        .frame(width: 240, height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    // MARK: - Nearby tab

    @ViewBuilder
    private var nearbyTabContent: some View {
        let rows = Array(discoverClubs.prefix(8))
        if rows.isEmpty {
            emptyDiscoverState(icon: "location", title: "No clubs nearby", subtitle: "Try a different category or create one.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, club in
                    Button { selectedClub = club } label: {
                        discoverClubRow(club)
                    }
                    .buttonStyle(.plain)
                    if idx < rows.count - 1 { inRowDivider }
                }
            }
        }
    }

    // MARK: - Friends tab

    @ViewBuilder
    private var friendsTabContent: some View {
        if friendsDiscoverClubs.isEmpty {
            emptyDiscoverState(
                icon: "person.2.slash",
                title: "No friends' clubs yet",
                subtitle: "When your friends join clubs, they show up here."
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(friendsDiscoverClubs.prefix(8).enumerated()), id: \.element.id) { idx, club in
                    Button { selectedClub = club } label: {
                        friendsClubRow(club)
                    }
                    .buttonStyle(.plain)
                    if idx < min(friendsDiscoverClubs.count, 8) - 1 { inRowDivider }
                }
            }
        }
    }

    /// Row variant that leads with a friend avatar stack — social-proof
    /// first, name + quick-join CTA second.
    @ViewBuilder
    private func friendsClubRow(_ club: Club) -> some View {
        let friends = friendsInClub(club)
        let friendUsers = friendUsersInClub(club)
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                clubAvatar(club, size: 46)
                if !friendUsers.isEmpty {
                    friendAvatarStack(friendUsers, size: 18)
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(club.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    if club.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(GQGradients.primary)
                    }
                    if !club.isOpen {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(GQColors.textTertiary)
                    }
                }
                if let firstName = firstFriendNameInClub(club) {
                    Text(friends == 1
                         ? "\(firstName) is in · \(club.memberCount) members"
                         : "\(firstName) + \(friends - 1) friends · \(club.memberCount) members")
                        .font(.system(size: 12))
                        .foregroundColor(GQColors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Button {
                do {
                    try ClubService.shared.joinClub(clubId: club.id, userId: profile.id)
                } catch {
                    print("Join failed: \(error.localizedDescription)")
                }
            } label: {
                Text(club.isOpen ? "Join" : "Request")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(GQGradients.primary))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// Resolve friend UUIDs in a club to name strings so we can render
    /// stacked monogram avatars.
    private func friendUsersInClub(_ club: Club) -> [(id: UUID, name: String)] {
        let followedIds = Set(SocialSeeder.fakeUsers.prefix(5).map(\.id))
        let matchIds = club.memberIds.filter { followedIds.contains($0) }
        return matchIds.compactMap { id in
            guard let u = SocialSeeder.fakeUsers.first(where: { $0.id == id }) else { return nil }
            return (id, u.name)
        }
    }

    /// Up-to-3 mini avatar circles, stacked slightly — used as a social-
    /// proof overlay on friends-tab club rows.
    @ViewBuilder
    private func friendAvatarStack(_ friends: [(id: UUID, name: String)], size: CGFloat) -> some View {
        HStack(spacing: -size * 0.4) {
            ForEach(Array(friends.prefix(3).enumerated()), id: \.element.id) { _, friend in
                Circle()
                    .fill(GQGradients.primary)
                    .frame(width: size, height: size)
                    .overlay(
                        Text(String(friend.name.prefix(1)).uppercased())
                            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    )
                    .overlay(Circle().stroke(GQColors.background, lineWidth: 1.5))
            }
        }
    }

    // MARK: - Challenges tab

    @ViewBuilder
    private var challengesTabContent: some View {
        let rows = Array((myActiveChallenges + joinableChallenges).prefix(6))
        if rows.isEmpty {
            emptyDiscoverState(
                icon: "flag.checkered",
                title: "No active challenges",
                subtitle: "Challenges will appear when clubs start one."
            )
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { idx, challenge in
                    challengeRow(challenge)
                    if idx < rows.count - 1 {
                        inRowDivider
                    }
                }
            }
        }
    }

    /// Challenge rendered as an inline row (no nested card) so it
    /// sits cleanly inside the grouped Discover card.
    @ViewBuilder
    private func challengeRow(_ challenge: ClubChallenge) -> some View {
        let club = allClubs.first(where: { $0.id == challenge.clubId })
        let isJoined = challenge.participantIds.contains(profile.id)
        let daysLeft = challenge.daysRemaining

        Button {
            if let c = club { selectedClub = c }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(GQGradients.primary.opacity(0.14))
                            .frame(width: 36, height: 36)
                        Image(systemName: challenge.goalType.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GQGradients.primary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(challenge.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)
                            .lineLimit(1)
                        Text(club?.name ?? "Club")
                            .font(.system(size: 11))
                            .foregroundColor(GQColors.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(daysLeft == 0 ? "ENDS TODAY" : "\(daysLeft)D LEFT")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.4)
                        .foregroundColor(daysLeft <= 2 ? .white : GQColors.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(
                            daysLeft <= 2 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(GQColors.adaptiveOverlay(0.08))
                        ))
                }

                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(GQColors.adaptiveOverlay(0.08))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(GQGradients.primary)
                                .frame(width: max(4, geo.size.width * challenge.progress))
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text("\(challenge.currentProgress) / \(challenge.goalTarget) \(challenge.goalType.rawValue.lowercased())")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(GQColors.textSecondary)
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text("\(challenge.participantIds.count)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(GQColors.textTertiary)
                    }
                }

                HStack(spacing: 0) {
                    Text(isJoined ? "Joined" : "Join Challenge")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(GQGradients.primary))
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Challenge card — progress bar + participants + join CTA. Tapping
    /// the card opens the parent club so the user can see context.
    @ViewBuilder
    private func challengeCard(_ challenge: ClubChallenge) -> some View {
        let club = allClubs.first(where: { $0.id == challenge.clubId })
        let isJoined = challenge.participantIds.contains(profile.id)
        let daysLeft = challenge.daysRemaining
        let participants = challenge.participantIds.count

        Button {
            if let c = club { selectedClub = c }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Top row — icon + title + urgency pill
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(GQGradients.primary.opacity(0.14))
                            .frame(width: 38, height: 38)
                        Image(systemName: challenge.goalType.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(GQGradients.primary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(challenge.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)
                            .lineLimit(1)
                        Text(club?.name ?? "Club")
                            .font(.system(size: 11))
                            .foregroundColor(GQColors.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    Text(daysLeft == 0 ? "ENDS TODAY" : "\(daysLeft)D LEFT")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.4)
                        .foregroundColor(daysLeft <= 2 ? .white : GQColors.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(
                            daysLeft <= 2 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(GQColors.adaptiveOverlay(0.08))
                        ))
                }

                // Progress bar
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(GQColors.adaptiveOverlay(0.08))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(GQGradients.primary)
                                .frame(width: max(4, geo.size.width * challenge.progress))
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text("\(challenge.currentProgress) / \(challenge.goalTarget) \(challenge.goalType.rawValue.lowercased())")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(GQColors.textSecondary)
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text("\(participants)")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(GQColors.textTertiary)
                    }
                }

                // Action row
                HStack(spacing: 8) {
                    if isJoined {
                        Text("Joined")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(GQGradients.primary))
                    } else {
                        Text("Join Challenge")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(GQGradients.primary))
                    }
                    if let c = club {
                        Text("View \(c.name)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(GQColors.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(GQColors.adaptiveOverlay(0.06)))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(14)
            .background(GQColors.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(GQColors.borderDefault.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    @ViewBuilder
    private func emptyDiscoverState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(GQColors.textTertiary)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(GQColors.textSecondary)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(GQColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
    }

    /// Shown when the active category filter hides every section —
    /// nudges the user to clear the filter instead of staring at a
    /// blank page.
    @ViewBuilder
    private var filterEmptyStateBlock: some View {
        VStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 26))
                .foregroundColor(GQColors.textTertiary)
            Text("No clubs match \(selectedCategory?.rawValue ?? "this filter")")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(GQColors.textSecondary)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { selectedCategory = nil }
            } label: {
                Text("Clear filter")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(GQGradients.primary))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    /// Empty state — only shown when the user has zero clubs AND there
    /// are no recommendations. Nudges them to browse or create.
    @ViewBuilder
    private var emptyStateBlock: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(GQGradients.primary.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
            }
            VStack(spacing: 4) {
                Text("No clubs yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Text("Browse nearby clubs or start your own.")
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textTertiary)
            }
            HStack(spacing: 10) {
                Button { presentingSearch = true } label: {
                    Text("Browse")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(GQColors.adaptiveOverlay(0.08)))
                }
                .buttonStyle(.plain)
                Button { showingCreateClub = true } label: {
                    Text("Create Club")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(GQGradients.primary))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    /// Search sheet — reuses the existing search-result UI so the old
    /// in-page search bar is gone. Keeps categories as chips inside
    /// the sheet rather than cluttering the landing.
    @ViewBuilder
    private var clubSearchSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !searchText.isEmpty {
                            searchResultsSection
                        } else {
                            categoriesGrid
                        }
                        Spacer(minLength: 60)
                    }
                    .padding(.top, 8)
                }
            }
            .gqPageBackground()
            .navigationTitle("Search Clubs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        searchText = ""
                        presentingSearch = false
                    }
                    .foregroundColor(GQColors.textPrimary)
                }
            }
        }
    }

    // MARK: - Right-now summary card (addictive morning-digest)

    /// Live count across all clubs the user is in. Friends who are in the
    /// same clubs get special mention because social proof → stickiness.
    private var liveInMyClubs: Int {
        let memberIds = Set(yourClubs.flatMap { $0.memberIds }).subtracting([profile.id])
        return presenceStates.filter { memberIds.contains($0.userId) && $0.status == .training }.count
    }

    /// Count of events today across all clubs.
    private var eventsTodayCount: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: today) else { return 0 }
        return allEvents.filter { $0.date >= today && $0.date < tomorrow }.count
    }

    @ViewBuilder
    private var rightNowCard: some View {
        let live = liveInMyClubs
        let eventsToday = eventsTodayCount

        if live > 0 || eventsToday > 0 {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(GQGradients.primary.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: live > 0 ? "figure.strengthtraining.traditional" : "calendar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GQGradients.primary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(rightNowHeadline(live: live, eventsToday: eventsToday))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    Text(rightNowSubtitle(live: live, eventsToday: eventsToday))
                        .font(.system(size: 11))
                        .foregroundColor(GQColors.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
            }
            .padding(12)
            .homeSocialCard(cornerRadius: 14)
            .padding(.horizontal, 16)
            .onTapGesture {
                if live > 0, let club = yourClubs.first { selectedClub = club }
                else if eventsToday > 0, let first = upcomingEvents.first,
                        let club = allClubs.first(where: { $0.id == first.clubId }) {
                    selectedClub = club
                }
            }
        }
    }

    private func rightNowHeadline(live: Int, eventsToday: Int) -> String {
        if live > 0 { return "\(live) training now in your clubs" }
        if eventsToday == 1 { return "1 event today in your clubs" }
        return "\(eventsToday) events today in your clubs"
    }

    private func rightNowSubtitle(live: Int, eventsToday: Int) -> String {
        if live > 0 && eventsToday > 0 { return "Plus \(eventsToday) event\(eventsToday == 1 ? "" : "s") happening today" }
        if live > 0 { return "Tap in to cheer or join them" }
        return "Tap to see what's happening"
    }

    // MARK: - Active now rail (members in your clubs training right now)

    @ViewBuilder
    private var activeNowRail: some View {
        if !activeMembersInMyClubs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(GQColors.success)
                        .frame(width: 8, height: 8)
                    Text("ACTIVE NOW IN YOUR CLUBS")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(GQColors.textTertiary)
                        .tracking(0.6)
                    Spacer()
                    Text("\(activeMembersInMyClubs.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(GQColors.textTertiary)
                }
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(activeMembersInMyClubs.prefix(10), id: \.userId) { member in
                            activeMemberCell(member)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func activeMemberCell(_ m: (userId: UUID, name: String, workoutType: String?, clubName: String)) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(GQColors.success, lineWidth: 1.5)
                    .frame(width: 44, height: 44)
                Circle()
                    .fill(GQGradients.primary)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Text(String(m.name.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    )
                Circle()
                    .fill(GQColors.success)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(GQColors.background, lineWidth: 1.5))
                    .frame(width: 44, height: 44, alignment: .bottomTrailing)
            }
            Text(m.name.components(separatedBy: " ").first ?? m.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(GQColors.textPrimary)
                .lineLimit(1)
            Text((m.workoutType?.capitalized) ?? "Training")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(GQColors.textTertiary)
                .lineLimit(1)
        }
        .frame(width: 58)
    }

    // MARK: - Events rails (my clubs first, nearby second)

    /// Events in clubs the user is already in — top-priority section
    /// so they never miss a meetup.
    @ViewBuilder
    private var eventsInYourClubsRail: some View {
        if !upcomingEventsInMyClubs.isEmpty {
            eventsRail(
                title: "IN YOUR CLUBS",
                events: Array(upcomingEventsInMyClubs.prefix(10))
            )
        }
    }

    /// Events in nearby / recommended clubs — discovery hook.
    /// Empty state shows the CTA card when BOTH rails are empty.
    @ViewBuilder
    private var upcomingEventsRail: some View {
        if !upcomingEventsNearby.isEmpty {
            eventsRail(
                title: "NEARBY EVENTS",
                events: Array(upcomingEventsNearby.prefix(10))
            )
        } else if upcomingEventsInMyClubs.isEmpty {
            // Nothing anywhere — show the empty-state CTA so the page
            // never reads as broken.
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("HAPPENING NEAR YOU")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(GQColors.textTertiary)
                        .tracking(0.6)
                    Spacer()
                }
                .padding(.horizontal, 20)
                upcomingEventsEmptyCard
            }
        }
    }

    @ViewBuilder
    private func eventsRail(title: String, events: [ClubEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
                    .tracking(0.6)
                Spacer()
                Text("\(events.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
            }
            .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(events) { event in
                        upcomingEventCard(event)
                            .onTapGesture {
                                if let club = allClubs.first(where: { $0.id == event.clubId }) {
                                    selectedClub = club
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func upcomingEventCard(_ event: ClubEvent) -> some View {
        let club = allClubs.first(where: { $0.id == event.clubId })
        let isGoing = event.attendeeIds.contains(profile.id)

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(GQGradients.primary.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: event.eventType.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GQGradients.primary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(eventDayLabel(event.date))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(GQGradients.primary)
                        .tracking(0.4)
                    Text(event.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                }

                Spacer(minLength: 0)
            }

            Text(event.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(GQColors.textPrimary)
                .lineLimit(2)

            if let club {
                Text(club.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(GQColors.textSecondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                if let loc = event.location ?? club?.location, !loc.isEmpty {
                    Image(systemName: "mappin")
                        .font(.system(size: 10, weight: .semibold))
                    Text(loc)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("\(event.attendeeIds.count)")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(isGoing ? .white : GQColors.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(isGoing ? AnyShapeStyle(GQGradients.primary) : AnyShapeStyle(GQColors.adaptiveOverlay(0.06)))
                )
            }
            .foregroundColor(GQColors.textTertiary)
        }
        .padding(12)
        .frame(width: 220, alignment: .leading)
        .homeSocialCard(cornerRadius: 14)
    }

    @ViewBuilder
    private var upcomingEventsEmptyCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(GQGradients.primary.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("No events near you yet")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Text("Join a club or start one — meet up in person.")
                    .font(.system(size: 12))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .homeSocialCard(cornerRadius: 14)
        .padding(.horizontal, 16)
    }

    private func eventDayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "TODAY" }
        if cal.isDateInTomorrow(date) { return "TOMORROW" }
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE, MMM d"
        return fmt.string(from: date).uppercased()
    }

    // MARK: - Featured carousel (legacy, no longer rendered — kept for reference)

    /// Big horizontal cards — top clubs by member count. Prefers non-
    /// joined clubs with a location so the rail biases toward
    /// discovery, but falls back to *any* top-level club (joined
    /// included) so the page doesn't look bare when the recommendation
    /// pool is thin.
    private var featuredClubs: [Club] {
        let nonJoinedWithLoc = recommendedClubs
            .filter { $0.location != nil && $0.parentClubId == nil }
        let nonJoined = recommendedClubs.filter { $0.parentClubId == nil }
        let pool: [Club]
        if !nonJoinedWithLoc.isEmpty {
            pool = nonJoinedWithLoc
        } else if !nonJoined.isEmpty {
            pool = nonJoined
        } else {
            // Absolute fallback — highlight the user's own largest clubs
            // so the rail always shows something. Keeps the page alive
            // even for users who've joined everything near them.
            pool = topLevelClubs
        }
        return Array(pool
            .sorted { ($0.memberCount, ($0.lastActivityDate ?? .distantPast)) > ($1.memberCount, ($1.lastActivityDate ?? .distantPast)) }
            .prefix(5))
    }

    @ViewBuilder
    private var featuredCarousel: some View {
        if !featuredClubs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("FEATURED")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
                    .tracking(0.6)
                    .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(featuredClubs) { club in
                            featuredCard(club)
                                .onTapGesture { selectedClub = club }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    @ViewBuilder
    private func featuredCard(_ club: Club) -> some View {
        let cat = club.resolvedCategory
        ZStack(alignment: .bottomLeading) {
            ClubCoverImage(club: club, fallbackGradient: GQGradients.primary)
                .frame(width: 220, height: 150)
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.15), .black.opacity(0.65)],
                startPoint: .top, endPoint: .bottom
            )

            // Top-left category pill
            VStack {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: cat.icon)
                            .font(.system(size: 9, weight: .bold))
                        Text(cat.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.ultraThinMaterial))
                    Spacer()
                }
                Spacer()
            }
            .padding(12)

            // Bottom: name + meta
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(club.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    if club.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.95))
                    }
                }
                HStack(spacing: 5) {
                    if let loc = club.location, !loc.isEmpty {
                        Image(systemName: "mappin")
                            .font(.system(size: 9, weight: .semibold))
                        Text(loc)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    } else {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(club.memberCount) members")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .foregroundColor(.white.opacity(0.9))
            }
            .padding(12)
        }
        .frame(width: 220, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    // MARK: - Categories grid

    /// Full-width browse menu. Ordered so activity-based categories come
    /// first, then sports, then specialty. Users can scroll to see all.
    private var browseCategories: [ClubCategory] {
        [.running, .weightlifting, .yoga, .hiit, .crossfit, .cycling,
         .swimming, .climbing, .basketball, .soccer, .tennis, .martialArts,
         .dance, .volleyball, .generalFitness]
    }

    @ViewBuilder
    private var categoriesGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("BROWSE")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
                    .tracking(0.6)
                Spacer()
                if selectedCategory != nil {
                    Button("Clear") {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedCategory = nil }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
                }
            }
            .padding(.horizontal, 20)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                ForEach(browseCategories, id: \.self) { cat in
                    categoryTile(cat)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func categoryTile(_ cat: ClubCategory) -> some View {
        let isSelected = selectedCategory == cat
        let count = allClubs.filter { $0.resolvedCategory == cat && $0.parentClubId == nil }.count
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = isSelected ? nil : cat
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(GQColors.deepBlue.opacity(0.15))
                        .frame(width: 34, height: 34)
                    Image(systemName: cat.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(GQGradients.primary)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(cat.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    if count > 0 {
                        Text("\(count) nearby")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(GQColors.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? AnyShapeStyle(GQGradients.primary.opacity(0.10)) : AnyShapeStyle(GQColors.surfaceBase))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isSelected ? AnyShapeStyle(GQGradients.primary) : AnyShapeStyle(GQColors.borderDefault.opacity(0.4)),
                                lineWidth: isSelected ? 1.5 : 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Your clubs shelf (compact horizontal)

    @ViewBuilder
    private var yourClubsShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOUR CLUBS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
                    .tracking(0.6)
                Spacer()
                Text("\(yourClubs.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
            }
            .padding(.horizontal, 20)

            yourClubsSortChips

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(sortedYourClubs) { club in
                        Button { selectedClub = club } label: {
                            VStack(spacing: 8) {
                                yourClubAvatar(club)
                                Text(club.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(GQColors.textPrimary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 72)
                                yourClubSubtitle(for: club)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /// Compact sort chips above the shelf. Only meaningful once the user is
    /// in a few clubs — hidden below 3 so it doesn't add chrome for light users.
    @ViewBuilder
    private var yourClubsSortChips: some View {
        if yourClubs.count >= 3 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(YourClubsSort.allCases) { sort in
                        let selected = yourClubsSort == sort
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { yourClubsSort = sort }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: sort.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(sort.label)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(selected ? .white : GQColors.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Group {
                                    if selected {
                                        GQGradients.primary
                                    } else {
                                        GQColors.surfaceBase
                                    }
                                }
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(
                                    selected ? Color.clear : GQColors.borderDefault,
                                    lineWidth: 1
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /// Tiny subtitle under each avatar name. Shows the signal that matches
    /// the active sort — distance when sorting by Nearby, next event date
    /// when sorting by Up next, live count when sorting by Active. Keeps the
    /// shelf scannable at 100+ clubs.
    @ViewBuilder
    private func yourClubSubtitle(for club: Club) -> some View {
        switch yourClubsSort {
        case .recent:
            EmptyView()
        case .nearby:
            if let dist = distanceString(for: club) {
                Text(dist)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(GQColors.textTertiary)
                    .frame(width: 72)
            }
        case .upNext:
            if let ev = nextEvent(for: club) {
                Text(eventDayLabel(ev.date))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(GQColors.deepBlue)
                    .frame(width: 72)
                    .lineLimit(1)
            }
        case .active:
            let live = liveCount(for: club)
            if live > 0 {
                HStack(spacing: 3) {
                    Circle().fill(GQColors.success).frame(width: 5, height: 5)
                    Text("\(live) live")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(GQColors.success)
                }
                .frame(width: 72)
            }
        }
    }

    // MARK: - Search results section

    @ViewBuilder
    private var searchResultsSection: some View {
        let matches = (yourClubs + recommendedClubs).filter { matchesSearch($0) }
        if matches.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundColor(GQColors.textTertiary)
                Text("No clubs match \"\(searchText)\"")
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(spacing: 10) {
                ForEach(matches) { club in
                    recommendedClubCard(club)
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundColor(GQColors.textTertiary)
            TextField("Search clubs, locations, activities", text: $searchText)
                .font(.system(size: 15))
                .foregroundColor(GQColors.textPrimary)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(GQColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(GQColors.adaptiveOverlay(0.08))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    // MARK: - Category Pills + Toggle Row

    private var categoryAndToggleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryPill(label: "All", icon: nil, isSelected: selectedCategory == nil) {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedCategory = nil }
                }
                ForEach(activeCategories, id: \.self) { cat in
                    categoryPill(label: cat.rawValue, icon: cat.icon, isSelected: selectedCategory == cat) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = selectedCategory == cat ? nil : cat
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var viewModeToggle: some View {
        HStack(spacing: 0) {
            viewModeButton(icon: "list.bullet", mode: .list)
            viewModeButton(icon: "map", mode: .map)
        }
        .background(GQColors.adaptiveOverlay(0.06))
        .cornerRadius(8)
    }

    @ViewBuilder
    private func viewModeButton(icon: String, mode: ClubViewMode) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { clubViewMode = mode }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(clubViewMode == mode ? GQColors.textPrimary : GQColors.textTertiary)
                .frame(width: 32, height: 30)
                .background(clubViewMode == mode ? GQColors.adaptiveOverlay(0.12) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - List Mode

    @ViewBuilder
    private var listModeContent: some View {
        yourClubHeroCard
            .padding(.horizontal, 16)
        featuredChallengeCard
            .padding(.horizontal, 16)
        myClubsSection
        nearbySection
        createClubButton
    }

    // MARK: - Your Club Hero Card

    @ViewBuilder
    private var yourClubHeroCard: some View {
        if let club = yourClubs.first {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    // Club icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(GQGradients.primary.opacity(0.08))
                            .frame(width: 48, height: 48)
                        Image(systemName: club.resolvedCategory.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(GQGradients.primary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(club.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(GQColors.textPrimary)
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 11))
                            Text(memberCountText(club.memberCount))
                                .font(.system(size: 13))
                        }
                        .foregroundColor(GQColors.textTertiary)
                    }

                    Spacer()
                }

                Button {
                    selectedClub = club
                } label: {
                    Text("Open Club")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(GQGradients.primary, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(GQColors.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(GQColors.borderDefault, lineWidth: 1))
            )
        }
    }

    // MARK: - Featured Challenge Card

    @ViewBuilder
    private var featuredChallengeCard: some View {
        if let challenge = featuredChallenge {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    Text("Active Challenge")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                    Spacer()
                }

                Text(challenge.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(GQColors.textPrimary)

                if !challenge.challengeDescription.isEmpty {
                    Text(challenge.challengeDescription)
                        .font(.system(size: 13))
                        .foregroundColor(GQColors.textSecondary)
                        .lineLimit(2)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(GQColors.surfaceOverlay)
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(GQGradients.primary)
                            .frame(width: geo.size.width * min(1.0, challenge.progress), height: 8)
                    }
                }
                .frame(height: 8)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(GQColors.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            )
        }
    }

    // MARK: - My Clubs Section

    @ViewBuilder
    private var myClubsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("MY CLUBS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
                    .tracking(0.6)

                if !yourClubs.isEmpty {
                    Text("\(yourClubs.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(GQColors.textTertiary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)

            if searchFilteredYourClubs.isEmpty && !yourClubs.isEmpty {
                Text("No matching clubs")
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else if yourClubs.isEmpty {
                emptyClubsState
            } else {
                ForEach(searchFilteredYourClubs) { club in
                    clubCard(club)
                        .onTapGesture { selectedClub = club }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyClubsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 30))
                .foregroundStyle(GQGradients.primary)
            Text("No Clubs Yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(GQColors.textPrimary)
            Text("Join a club to find your people and get matched into an accountability pod")
                .font(.system(size: 13))
                .foregroundColor(GQColors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                withAnimation {
                    searchText = " "
                    searchText = ""
                }
            } label: {
                Text("Discover Clubs Below")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.deepBlue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(GQColors.deepBlue.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .homeSocialCard(cornerRadius: 14, subtle: true)
        .padding(.horizontal, 16)
    }

    // MARK: - Nearby / Discover Section

    @ViewBuilder
    private var nearbySection: some View {
        // Split into "Nearby" (has location) vs "Online" (virtual/no-location)
        // so location-first browsing feels intentional. When a category filter
        // returns zero matches, show a proper empty-state card instead of
        // blank scroll space.
        let nearby = searchFilteredRecommended.filter { $0.location != nil }
        let online = searchFilteredRecommended.filter { $0.location == nil }

        VStack(alignment: .leading, spacing: 14) {
            if searchFilteredRecommended.isEmpty {
                emptyRecommendedCard
            }

            if !nearby.isEmpty {
                sectionHeader("NEARBY", trailingText: "\(nearby.count)")
                ForEach(nearby) { club in recommendedClubCard(club) }
            }

            if !online.isEmpty {
                sectionHeader("ONLINE", trailingText: "\(online.count)")
                ForEach(online) { club in recommendedClubCard(club) }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, trailingText: String? = nil) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(GQColors.textTertiary)
                .tracking(0.6)
            Spacer()
            if let count = trailingText {
                Text(count)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    /// Empty state when a category filter (or search) returns no matching
    /// recommended clubs. Offers the Create CTA inline so the dead-end
    /// becomes an action.
    @ViewBuilder
    private var emptyRecommendedCard: some View {
        let filterName = selectedCategory?.rawValue ?? "clubs"
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(GQGradients.primary.opacity(0.7))
            Text("No \(filterName.lowercased()) clubs near you yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(GQColors.textPrimary)
                .multilineTextAlignment(.center)
            Text("Be the first to start one — other lifters nearby will see it too.")
                .font(.system(size: 12))
                .foregroundColor(GQColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Button { showingCreateClub = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("Create a \(filterName.capitalized) Club")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(GQGradients.primary))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .homeSocialCard(cornerRadius: 16)
        .padding(.horizontal, 16)
    }

    // MARK: - Map Mode

    @ViewBuilder
    private var mapModeContent: some View {
        ZStack(alignment: .bottom) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 44.225, longitude: -76.490),
                span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
            ))) {
                ForEach(clubsWithCoordinates) { club in
                    if let lat = club.latitude, let lng = club.longitude {
                        Annotation(club.name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                            mapPin(for: club)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .preferredColorScheme(.dark)
            .frame(height: 420)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { selectedMapClub = nil }
            }

            if let club = selectedMapClub {
                mapClubOverlay(club)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.25), value: selectedMapClub?.id)

        if clubsWithCoordinates.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "map")
                    .font(.system(size: 24))
                    .foregroundColor(GQColors.textTertiary)
                Text("No clubs with locations")
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private func mapPin(for club: Club) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedMapClub = club }
        } label: {
            Circle()
                .fill(club.resolvedCategory.color)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: club.resolvedCategory.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                )
                .shadow(color: club.resolvedCategory.color.opacity(0.4), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func mapClubOverlay(_ club: Club) -> some View {
        let isMember = club.memberIds.contains(profile.id)
        HStack(spacing: 12) {
            categoryIcon(for: club, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(club.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    if club.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundColor(GQColors.textSecondary)
                    }
                }
                HStack(spacing: 6) {
                    Text(club.resolvedCategory.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(club.resolvedCategory.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(club.resolvedCategory.color.opacity(0.15))
                        .cornerRadius(4)
                    if let loc = club.location {
                        Text(loc)
                            .font(.system(size: 11))
                            .foregroundColor(GQColors.textTertiary)
                    }
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(GQColors.textTertiary)
                    Text("\(club.memberCount)")
                        .font(.system(size: 11))
                        .foregroundColor(GQColors.textTertiary)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 9))
                        .foregroundColor(GQColors.textTertiary)
                }
            }

            Spacer(minLength: 0)

            if isMember {
                Button { selectedClub = club } label: {
                    Text("View")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(GQColors.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(GQColors.textSecondary.opacity(0.12))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    withAnimation {
                        do {
                            try ClubService.shared.joinClub(clubId: club.id, userId: profile.id)
                        } catch {
                            print("Failed to join club: \(error.localizedDescription)")
                        }
                    }
                } label: {
                    Text("Join")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(GQColors.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(GQColors.textSecondary.opacity(0.12))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(14)
    }

    // MARK: - Row cards (Apple-style: clean, no accent bars)

    @ViewBuilder
    private func clubCard(_ club: Club) -> some View {
        HStack(spacing: 12) {
            clubAvatar(club, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(club.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    if club.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(GQGradients.primary)
                    }
                }
                Text(cardMeta(for: club))
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(GQColors.textTertiary)
        }
        .padding(14)
        .homeSocialCard(cornerRadius: 14)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func recommendedClubCard(_ club: Club) -> some View {
        let live = liveCount(for: club)
        let next = nextEvent(for: club)
        let friends = friendsInClub(club)

        return HStack(alignment: .top, spacing: 12) {
            clubAvatar(club, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(club.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    if club.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(GQGradients.primary)
                    }
                }

                // Friend-in-club social proof chip — highest-priority
                // liveness signal, above the meta line so it's skimmable.
                if friends > 0, let name = firstFriendNameInClub(club) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text(friends == 1 ? "\(name) is in" : "\(name) + \(friends - 1) friend\(friends - 1 == 1 ? "" : "s") are in")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(GQGradients.primary)
                }

                // Meta: distance · members  (·  live)
                HStack(spacing: 6) {
                    Text(cardMeta(for: club))
                        .font(.system(size: 12))
                        .foregroundColor(GQColors.textTertiary)
                        .lineLimit(1)
                    if live > 0 {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(GQColors.success)
                                .frame(width: 6, height: 6)
                            Text("\(live) training now")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(GQColors.success)
                        }
                    }
                }

                // Next event teaser
                if let next {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(eventDayLabel(next.date)) · \(next.title)")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(GQGradients.primary)
                    .padding(.top, 1)
                }
            }

            Spacer(minLength: 8)

            Button {
                withAnimation {
                    do {
                        try ClubService.shared.joinClub(clubId: club.id, userId: profile.id)
                    } catch {
                        print("Failed to join club: \(error.localizedDescription)")
                    }
                }
            } label: {
                Text("Join")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(GQGradients.primary))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .homeSocialCard(cornerRadius: 14)
        .padding(.horizontal, 16)
    }

    /// Row metadata: distance (when coords) + members. Falls back to
    /// "Online · N members" for virtual clubs.
    private func cardMeta(for club: Club) -> String {
        let members = memberCountText(club.memberCount)
        if let d = distanceString(for: club) {
            return "\(d) · \(members)"
        }
        if let loc = club.location, !loc.isEmpty {
            return "\(loc) · \(members)"
        }
        return "Online · \(members)"
    }

    @ViewBuilder
    private func clubAvatar(_ club: Club, size: CGFloat) -> some View {
        #if canImport(UIKit)
        if let data = club.imageData, let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            categoryIcon(for: club, size: size)
        }
        #else
        categoryIcon(for: club, size: size)
        #endif
    }

    // MARK: - Helpers

    private func memberCountText(_ count: Int) -> String {
        count == 1 ? "1 member" : "\(count) members"
    }

    @ViewBuilder
    private func categoryPill(label: String, icon: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                }
                Text(label)
            }
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundColor(isSelected ? GQColors.textPrimary : GQColors.textTertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(GQColors.adaptiveOverlay(isSelected ? 0.12 : 0.06))
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }

    /// Monogram-style default avatar — first letter of the club name on a
    /// per-club gradient tile. Photo overrides this when imageData is set.
    private func categoryIcon(for club: Club, size: CGFloat) -> some View {
        ClubMonogramAvatar(club: club, size: size)
    }

    @ViewBuilder
    private var createClubButton: some View {
        Button(action: { showingCreateClub = true }) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("Create a Club")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(GQGradients.primary, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - Club Preview Card (for empty state)

struct ClubPreviewCard: View {
    let name: String
    let members: Int
    let location: String
    let isVerified: Bool
    var category: ClubCategory = .generalFitness
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(category.color.opacity(0.15))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: category.icon)
                            .font(.system(size: 20))
                            .foregroundColor(category.color)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)
                            .lineLimit(1)

                        if isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(GQColors.textSecondary)
                        }
                    }

                    HStack(spacing: 8) {
                        Label("\(members)", systemImage: "person.2.fill")
                        Text("•")
                        Text(location)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(GQColors.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(GQColors.textTertiary)
            }
            .padding(14)
            .homeSocialCard(cornerRadius: 12, subtle: true)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }
}

// MARK: - Club Card (for joined clubs)

struct ClubCard: View {
    let club: Club
    let profile: UserProfile

    var body: some View {
        let cat = club.resolvedCategory
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if let imageData = club.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(GQColors.deepBlue.opacity(0.12))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Image(systemName: cat.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(GQGradients.primary)
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(club.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)
                            .lineLimit(1)

                        if club.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(GQColors.textSecondary)
                        }
                    }

                    HStack(spacing: 8) {
                        Label("\(club.memberCount)", systemImage: "person.2.fill")
                        if let location = club.location {
                            Text("•")
                            Text(location)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundColor(GQColors.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(GQColors.textTertiary)
            }

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(GQColors.deepBlue)
                        .frame(width: 6, height: 6)
                    Text("12 active today")
                        .font(.system(size: 11))
                        .foregroundColor(GQColors.textTertiary)
                }

                Spacer()

                Text("3 new posts")
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textSecondary)
            }
        }
        .padding(14)
        .homeSocialCard(cornerRadius: 12, subtle: true)
        .padding(.horizontal, 16)
    }
}

// MARK: - Create Club Sheet

struct CreateClubSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let profile: UserProfile

    @State private var name = ""
    @State private var description = ""
    @State private var location = ""
    @State private var joinType: ClubJoinType = .open
    @State private var category: ClubCategory = .generalFitness
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var clubImageData: Data?
    @State private var includeFirstChallenge = false
    @State private var challengeName = ""
    @State private var challengeTarget = 3

    var body: some View {
        NavigationStack {
            Form {
                Section("Club Image") {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Group {
                                #if canImport(UIKit)
                                if let clubImageData, let uiImage = UIImage(data: clubImageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                } else {
                                    Circle()
                                        .fill(GQColors.adaptiveOverlay(0.08))
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Image(systemName: "camera.fill")
                                                .font(.system(size: 24))
                                                .foregroundColor(GQColors.textTertiary)
                                        )
                                }
                                #else
                                Circle()
                                    .fill(GQColors.adaptiveOverlay(0.08))
                                    .frame(width: 80, height: 80)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(GQColors.textTertiary)
                                    )
                                #endif
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task {
                        if let data = try? await newItem?.loadTransferable(type: Data.self) {
                            clubImageData = data
                        }
                    }
                }

                Section("Club Info") {
                    TextField("Name (e.g., Queen's Run Club)", text: $name)
                    TextField("Location (optional)", text: $location)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Category") {
                    Picker("Activity Type", selection: $category) {
                        ForEach(ClubCategory.allCases, id: \.self) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                }

                Section("Privacy") {
                    Picker("Who can join?", selection: $joinType) {
                        Text("Anyone (Open)").tag(ClubJoinType.open)
                        Text("Request to Join").tag(ClubJoinType.request)
                    }
                }

                Section("First Challenge (Optional)") {
                    Toggle("Set up a launch challenge", isOn: $includeFirstChallenge)

                    if includeFirstChallenge {
                        TextField("Challenge name", text: $challengeName)
                        Stepper("Weekly target: \(challengeTarget) workouts", value: $challengeTarget, in: 1...7)
                    }
                }

                Section {
                    Text("Clubs are great for running groups, pickup sports, lifting crews, and more. Members can share activity, find partners, and join meetups.")
                        .font(.footnote)
                        .foregroundColor(GQColors.textTertiary)
                }
            }
            .navigationTitle("Create Club")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createClub()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert("Error", isPresented: $showCreateError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(createError ?? "An unexpected error occurred.")
        }
    }

    @State private var createError: String?
    @State private var showCreateError = false

    private func createClub() {
        do {
            let club = try ClubService.shared.createClub(
                name: name,
                description: description,
                category: category,
                joinType: joinType,
                creatorId: profile.id
            )

            // Apply optional fields not handled by the service
            if !location.isEmpty {
                club.location = location
            }
            if let imageData = clubImageData {
                club.imageData = imageData
            }

            if includeFirstChallenge && !challengeName.isEmpty {
                let challenge = ClubChallenge(
                    clubId: club.id,
                    title: challengeName,
                    challengeDescription: "Complete \(challengeTarget) workouts per week",
                    goalType: .workouts,
                    goalTarget: challengeTarget
                )
                modelContext.insert(challenge)
                try? modelContext.save()
            }

            dismiss()
        } catch {
            createError = error.localizedDescription
            showCreateError = true
        }
    }
}

// MARK: - Search Clubs Sheet

struct SearchClubsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allClubs: [Club]

    let profile: UserProfile

    @State private var searchText = ""
    @State private var filterCategory: ClubCategory? = nil

    var filteredClubs: [Club] {
        var clubs = allClubs.filter { $0.parentClubId == nil }
        if let cat = filterCategory {
            clubs = clubs.filter { $0.resolvedCategory == cat }
        }
        if !searchText.isEmpty {
            clubs = clubs.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.location?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.resolvedCategory.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }
        return clubs
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            filterCategory = nil
                        } label: {
                            Text("All")
                                .font(.system(size: 12, weight: filterCategory == nil ? .bold : .medium))
                                .foregroundColor(filterCategory == nil ? .white : GQColors.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(filterCategory == nil ? GQColors.deepBlue.opacity(0.4) : GQColors.adaptiveOverlay(0.08))
                                .cornerRadius(16)
                        }
                        .buttonStyle(.plain)

                        ForEach(ClubCategory.allCases, id: \.self) { cat in
                            Button {
                                filterCategory = filterCategory == cat ? nil : cat
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 10))
                                    Text(cat.rawValue)
                                }
                                .font(.system(size: 12, weight: filterCategory == cat ? .bold : .medium))
                                .foregroundColor(filterCategory == cat ? .white : GQColors.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(filterCategory == cat ? GQColors.deepBlue.opacity(0.25) : GQColors.adaptiveOverlay(0.08))
                                .cornerRadius(16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                List {
                    if filteredClubs.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundColor(GQColors.textTertiary)
                            Text("No clubs found")
                                .font(.headline)
                                .foregroundColor(GQColors.textPrimary)
                            Text("Try a different search or create your own")
                                .font(.subheadline)
                                .foregroundColor(GQColors.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredClubs) { club in
                            ClubSearchRow(
                                club: club,
                                isMember: club.memberIds.contains(profile.id),
                                onJoin: { joinClub(club) }
                            )
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search by name, location, or category")
            .navigationTitle("Find Clubs")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func joinClub(_ club: Club) {
        do {
            try ClubService.shared.joinClub(clubId: club.id, userId: profile.id)
        } catch {
            print("Failed to join club: \(error.localizedDescription)")
        }
    }
}

struct ClubSearchRow: View {
    let club: Club
    let isMember: Bool
    let onJoin: () -> Void

    var body: some View {
        let cat = club.resolvedCategory
        HStack(spacing: 12) {
            Circle()
                .fill(GQColors.deepBlue.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: cat.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(GQGradients.primary)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(club.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    if club.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundColor(GQColors.textSecondary)
                    }
                }

                HStack(spacing: 6) {
                    Text(club.memberCount == 1 ? "1 member" : "\(club.memberCount) members")
                    if let location = club.location {
                        Text("•")
                        Text(location)
                    }
                }
                .font(.system(size: 12))
                .foregroundColor(GQColors.textTertiary)
            }

            Spacer()

            if isMember {
                Text("Joined")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(GQColors.textTertiary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(GQColors.adaptiveOverlay(0.08))
                    .cornerRadius(8)
            } else {
                Button(action: onJoin) {
                    Text(club.joinType == .open ? "Join" : "Request")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(GQColors.deepBlue)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .listRowBackground(GQColors.adaptiveOverlay(0.04))
    }
}

// MARK: - Club Detail View

enum ClubSection: String, CaseIterable {
    case feed = "Feed"
    case pods = "Pods"
    case challenges = "Challenges"
    case events = "Events"
    case members = "Members"
    // Leaderboard removed — memo directive: clubs are community, not ranking.
    // Squad-scale leaderboards still exist for opt-in small groups.
}

struct ClubDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var clubPosts: [ClubPost]
    @Query private var allClubs: [Club]
    @Query private var allChallenges: [ClubChallenge]
    @Query private var allMemberships: [ClubMembership]
    @Query private var allEvents: [ClubEvent]
    @Query private var allClubMemberships: [ClubMembership]
    @Query private var presenceStates: [UserPresenceState]

    let club: Club
    let profile: UserProfile

    @State private var showingNewPost = false
    @State private var showingCreateEvent = false
    @State private var showingLeaveAlert = false
    @State private var selectedSection: ClubSection = .feed
    @State private var showPartnerOnly = false
    @State private var selectedChannelId: UUID? = nil
    @State private var clubServiceError: String?
    @State private var showClubServiceError = false

    private var isMember: Bool {
        club.memberIds.contains(profile.id)
    }

    private var posts: [ClubPost] {
        clubPosts
            .filter { post in
                post.clubId == club.id &&
                (selectedChannelId == nil || post.channelId == selectedChannelId)
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private var channels: [Club] {
        allClubs.filter { $0.parentClubId == club.id }
    }

    private var activeChallenges: [ClubChallenge] {
        allChallenges.filter { $0.clubId == club.id && $0.isActive }
    }

    private var memberships: [ClubMembership] {
        allMemberships.filter { $0.clubId == club.id }
    }

    private var clubEvents: [ClubEvent] {
        allEvents.filter { $0.clubId == club.id }
            .sorted { $0.date < $1.date }
    }

    /// Squad-kind Clubs that nest under this community club.
    private var clubSquads: [Club] {
        allClubs.filter { $0.kind == .squad && $0.parentClubId == club.id }
    }

    /// The user's own squad inside this community club (if they belong to one).
    private var userSquadInClub: Club? {
        let userSquadIds = Set(allClubMemberships.filter { $0.userId == profile.id }.map(\.clubId))
        return clubSquads.first { userSquadIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    detailHeader
                    activeInThisClubStrip
                    joinButton
                    clubSectionPicker
                    sectionContent
                    Spacer(minLength: 40)
                }
                .padding(.top, 8)
            }
            .gqPageBackground()
            .navigationTitle(club.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingNewPost) {
                NewClubPostSheet(club: club, profile: profile)
            }
            .alert("Leave Club", isPresented: $showingLeaveAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Leave", role: .destructive) {
                    leaveClub()
                }
            } message: {
                Text("Are you sure you want to leave \(club.name)?")
            }
            .sheet(isPresented: $showingCreateEvent) {
                CreateEventSheet(club: club, profile: profile)
            }
            .alert("Error", isPresented: $showClubServiceError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(clubServiceError ?? "An unexpected error occurred.")
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var detailHeader: some View {
        HStack(alignment: .top, spacing: 14) {
            // Avatar — per-club monogram matches the landing list
            #if canImport(UIKit)
            if let imageData = club.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 54, height: 54)
                    .clipShape(Circle())
            } else {
                ClubMonogramAvatar(club: club, size: 54)
            }
            #else
            ClubMonogramAvatar(club: club, size: 54)
            #endif

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Text(club.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(2)
                    if club.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(GQGradients.primary)
                    }
                }

                if !club.clubDescription.isEmpty {
                    Text(club.clubDescription)
                        .font(.system(size: 13))
                        .foregroundColor(GQColors.textSecondary)
                        .lineLimit(3)
                }

                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(club.memberCount == 1 ? "1 member" : "\(club.memberCount) members")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(GQColors.textTertiary)

                    if let location = club.location {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin")
                                .font(.system(size: 10, weight: .semibold))
                            Text(location)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundColor(GQColors.textTertiary)
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .homeSocialCard(cornerRadius: 16)
        .padding(.horizontal, 16)
    }

    // MARK: - Active Now (this club)

    /// Members of THIS club training right now. Matches the Friends feed
    /// ACTIVE NOW rail but scoped to the single club.
    @ViewBuilder
    private var activeInThisClubStrip: some View {
        let live = liveMembersInThisClub
        if !live.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(GQColors.success)
                        .frame(width: 6, height: 6)
                    Text("ACTIVE NOW")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundColor(GQColors.textTertiary)
                    Text("·").foregroundColor(GQColors.textTertiary)
                    Text("\(live.count) training now")
                        .font(.system(size: 10))
                        .foregroundColor(GQColors.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(live, id: \.userId) { m in
                            activeInClubCell(m)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var liveMembersInThisClub: [(userId: UUID, name: String, workoutType: String?)] {
        let memberIds = Set(club.memberIds).subtracting([profile.id])
        return presenceStates
            .filter { $0.status == .training && memberIds.contains($0.userId) }
            .compactMap { state in
                let name = SocialSeeder.fakeUsers.first(where: { $0.id == state.userId })?.name
                    ?? "Member"
                return (state.userId, name, state.workoutTypeRaw)
            }
    }

    @ViewBuilder
    private func activeInClubCell(_ m: (userId: UUID, name: String, workoutType: String?)) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Circle()
                    .stroke(GQColors.success, lineWidth: 1.5)
                    .frame(width: 44, height: 44)
                Circle()
                    .fill(GQGradients.primary)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Text(String(m.name.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    )
                Circle()
                    .fill(GQColors.success)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(GQColors.background, lineWidth: 1.5))
                    .frame(width: 44, height: 44, alignment: .bottomTrailing)
            }
            Text(m.name.components(separatedBy: " ").first ?? m.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(GQColors.textPrimary)
                .lineLimit(1)
            Text((m.workoutType?.capitalized) ?? "Training")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(GQColors.textTertiary)
                .lineLimit(1)
        }
        .frame(width: 58)
    }

    // MARK: - Join Button

    @ViewBuilder
    private var joinButton: some View {
        if !isMember {
            Button {
                do {
                    try ClubService.shared.joinClub(clubId: club.id, userId: profile.id)
                } catch {
                    clubServiceError = error.localizedDescription
                    showClubServiceError = true
                }
            } label: {
                Text(club.isOpen ? "Join Club" : "Request to Join")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(GQGradients.primary, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        } else if club.pendingRequestIds.contains(profile.id) {
            Text("Request Pending")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(GQColors.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(GQColors.adaptiveOverlay(0.04))
                .cornerRadius(10)
                .padding(.horizontal, 16)
        } else if isMember && club.creatorId != profile.id {
            Button {
                showingLeaveAlert = true
            } label: {
                Text("Leave Club")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(GQColors.textSecondary.opacity(0.1))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(GQColors.textSecondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Who's Working Out

    @ViewBuilder
    private var workingOutNowRow: some View {
        let users = SocialSeeder.fakeUsers
        let activeNames: [String] = club.memberIds.compactMap { memberId in
            guard let user = users.first(where: { $0.id == memberId }) else { return nil }
            let hash = abs(memberId.hashValue)
            guard hash % 3 == 0 else { return nil }
            return user.name
        }.prefix(4).map { $0 }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(GQColors.success)
                    .frame(width: 8, height: 8)
                Text("TRAINING NOW")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
                    .tracking(0.8)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(activeNames, id: \.self) { name in
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .stroke(GQColors.success, lineWidth: 1.5)
                                    .frame(width: 44, height: 44)
                                Circle()
                                    .fill(GQGradients.primary)
                                    .frame(width: 38, height: 38)
                                    .overlay(
                                        Text(String(name.prefix(1)))
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundColor(.white)
                                    )
                                Circle()
                                    .fill(GQColors.success)
                                    .frame(width: 10, height: 10)
                                    .overlay(Circle().stroke(GQColors.background, lineWidth: 1.5))
                                    .frame(width: 44, height: 44, alignment: .bottomTrailing)
                            }
                            Text(name)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(GQColors.textPrimary)
                                .lineLimit(1)
                        }
                        .frame(width: 58)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Channels

    @ViewBuilder
    private var channelCards: some View {
        if !channels.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("CHANNELS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(GQColors.textTertiary)
                    .tracking(1)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        // "All" pill to clear channel filter
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                selectedChannelId = nil
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "rectangle.grid.2x2")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(selectedChannelId == nil ? .white : GQColors.textSecondary)
                                Text("All")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(selectedChannelId == nil ? .white : .white.opacity(0.7))
                                    .lineLimit(1)
                                Text("\(posts.count) posts")
                                    .font(.system(size: 10))
                                    .foregroundColor(GQColors.textTertiary)
                            }
                            .frame(width: 110, height: 80)
                            .background(selectedChannelId == nil ? GQColors.deepBlue.opacity(0.3) : GQColors.adaptiveOverlay(0.05))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(selectedChannelId == nil ? GQColors.deepBlue.opacity(0.5) : GQColors.textSecondary.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)

                        ForEach(channels) { channel in
                            let isSelected = selectedChannelId == channel.id
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    selectedChannelId = isSelected ? nil : channel.id
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "number")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(isSelected ? .white : GQColors.textSecondary)
                                    Text(channel.name)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                                        .lineLimit(1)
                                    Text("\(channel.memberCount) members")
                                        .font(.system(size: 10))
                                        .foregroundColor(GQColors.textTertiary)
                                }
                                .frame(width: 110, height: 80)
                                .background(isSelected ? GQColors.deepBlue.opacity(0.3) : GQColors.adaptiveOverlay(0.05))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(isSelected ? GQColors.deepBlue.opacity(0.5) : GQColors.textSecondary.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: - Active Challenge Cards

    @ViewBuilder
    private var challengeCards: some View {
        ForEach(activeChallenges) { challenge in
            challengeCardView(challenge: challenge)
        }
    }

    @ViewBuilder
    private func challengeCardView(challenge: ClubChallenge) -> some View {
        let isJoined = challenge.participantIds.contains(profile.id)

        VStack(alignment: .leading, spacing: 12) {
            challengeCardHeader(challenge: challenge)
            challengeCardProgress(challenge: challenge)
            challengeJoinButton(challenge: challenge, isJoined: isJoined)
        }
        .padding(14)
        .homeSocialCard(cornerRadius: 14, subtle: true)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func challengeCardHeader(challenge: ClubChallenge) -> some View {
        HStack {
            Image(systemName: "trophy.fill")
                .foregroundColor(GQColors.textSecondary)
            Text("ACTIVE CHALLENGE")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(GQColors.textTertiary)
                .tracking(1)
            Spacer()
            Text("\(challenge.daysRemaining)d left")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(GQColors.textSecondary)
        }

        Text(challenge.title)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
    }

    @ViewBuilder
    private func challengeCardProgress(challenge: ClubChallenge) -> some View {
        AnimatedProgressBar(
            progress: challenge.progress,
            height: 8,
            colors: [GQColors.deepBlue, GQColors.textSecondary]
        )

        HStack {
            Text("\(challenge.currentProgress) / \(challenge.goalTarget) \(challenge.goalType.rawValue.lowercased())")
                .font(.system(size: 12))
                .foregroundColor(GQColors.textTertiary)
            Spacer()
            Text("\(challenge.participantIds.count) participating")
                .font(.system(size: 12))
                .foregroundColor(GQColors.textTertiary)
        }
    }

    @ViewBuilder
    private func challengeJoinButton(challenge: ClubChallenge, isJoined: Bool) -> some View {
        if isMember {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    if isJoined {
                        challenge.participantIds.removeAll { $0 == profile.id }
                    } else {
                        challenge.participantIds.append(profile.id)
                    }
                    try? modelContext.save()
                }
                #if canImport(UIKit)
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                #endif
            } label: {
                challengeJoinButtonLabel(isJoined: isJoined)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func challengeJoinButtonLabel(isJoined: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: isJoined ? "checkmark.circle.fill" : "flame.fill")
                .font(.system(size: 13))
            Text(isJoined ? "Joined" : "Join Challenge")
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            isJoined
                ? AnyShapeStyle(GQColors.elevatedSurface)
                : AnyShapeStyle(LinearGradient(colors: [GQColors.deepBlue, GQColors.textSecondary], startPoint: .leading, endPoint: .trailing))
        )
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isJoined ? GQColors.borderDefault : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        if isMember {
            HStack(spacing: 12) {
                Button { showingNewPost = true } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Post")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(GQColors.deepBlue)
                    .cornerRadius(10)
                }

                Button {
                    selectedSection = .members
                    showPartnerOnly = true
                } label: {
                    HStack {
                        Image(systemName: "person.2.fill")
                        Text("Find Partner")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(GQColors.textSecondary)
                    .cornerRadius(10)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - How This Club Works

    @ViewBuilder
    private var howThisClubWorksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(GQGradients.primary)
                Text("How This Club Works")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("Join challenges to compete with other members", systemImage: "trophy")
                Label("Get matched into a pod for weekly accountability", systemImage: "person.3.fill")
                Label("Share workouts and celebrate milestones together", systemImage: "hands.clap.fill")
            }
            .font(.system(size: 13))
            .foregroundColor(GQColors.textSecondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(GQColors.deepBlue.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(GQColors.borderDefault, lineWidth: 1))
        )
        .padding(.horizontal, 16)
    }

    // MARK: - Section Picker

    @ViewBuilder
    private var clubSectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ClubSection.allCases, id: \.self) { section in
                    let isSelected = selectedSection == section
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSection = section
                            if section != .members { showPartnerOnly = false }
                        }
                    } label: {
                        Text(section.rawValue)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? .white : GQColors.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(
                                    isSelected
                                        ? AnyShapeStyle(GQGradients.primary)
                                        : AnyShapeStyle(GQColors.adaptiveOverlay(0.05))
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Section Content

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .feed:
            VStack(spacing: 16) {
                workingOutNowRow
                channelCards
                actionButtons
                clubFeedSection
            }
        case .pods:
            clubPodsSection
        case .challenges:
            clubChallengesSection
        case .events:
            clubEventsSection
        case .members:
            clubMembersSection
        }
    }

    // MARK: - Squads Section (ClubKind.squad nested under this community Club)

    @ViewBuilder
    private var clubPodsSection: some View {
        VStack(spacing: 16) {
            // User's current squad in this club
            if let mySquad = userSquadInClub {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "target")
                            .foregroundStyle(GQGradients.primary)
                        Text("Your Squad")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(mySquad.name)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(GQColors.textPrimary)

                        Text("\(mySquad.memberIds.count)/\(mySquad.maxMembers ?? 6) members · \(mySquad.weeklyWorkoutTarget ?? 3)×/week target · \(mySquad.streakWeeks ?? 0) week streak")
                            .font(.system(size: 13))
                            .foregroundColor(GQColors.textSecondary)

                        if !mySquad.clubDescription.isEmpty {
                            Text(mySquad.clubDescription)
                                .font(.system(size: 13))
                                .foregroundColor(GQColors.textTertiary)
                        }
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(GQColors.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(GQColors.borderDefault, lineWidth: 1)
                        )
                )
            }

            // Other squads in this club
            let otherSquads = clubSquads.filter { $0.id != userSquadInClub?.id }
            if otherSquads.isEmpty && userSquadInClub == nil {
                VStack(spacing: 10) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 30))
                        .foregroundColor(GQColors.textTertiary)
                    Text("No Squads Yet")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(GQColors.textSecondary)
                    Text("Squads are small accountability groups. Create one to get started.")
                        .font(.system(size: 13))
                        .foregroundColor(GQColors.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ForEach(otherSquads, id: \.id) { squad in
                    squadRow(squad)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func squadRow(_ squad: Club) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 16))
                .foregroundStyle(GQGradients.primary)
                .frame(width: 36, height: 36)
                .background(GQColors.deepBlue.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(squad.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)

                Text("\(squad.memberIds.count)/\(squad.maxMembers ?? 6) · \(squad.clubLevel?.rawValue ?? "Any") · \(squad.weeklyWorkoutTarget ?? 3)×/wk")
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textSecondary)
            }

            Spacer()

            if !squad.isFull && !squad.memberIds.contains(profile.id) {
                Button("Join") {
                    squad.memberIds.append(profile.id)
                    let membership = ClubMembership(userId: profile.id, clubId: squad.id)
                    modelContext.insert(membership)
                    try? modelContext.save()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(GQGradients.primary, in: Capsule())
            } else if squad.isFull {
                Text("Full")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(GQColors.textTertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(GQColors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(GQColors.borderDefault, lineWidth: 1)
                )
        )
    }

    // MARK: - Challenges Tab Section

    @ViewBuilder
    private var clubChallengesSection: some View {
        if activeChallenges.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "trophy")
                    .font(.system(size: 30))
                    .foregroundColor(GQColors.textTertiary)
                Text("No active challenges")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(GQColors.textSecondary)
                Text("Check back soon for new challenges")
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
        } else {
            challengeCards
        }
    }

    // MARK: - Events Section

    @ViewBuilder
    private var clubEventsSection: some View {
        VStack(spacing: 12) {
            if isMember {
                Button {
                    showingCreateEvent = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Create Event")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [GQColors.deepBlue, GQColors.textSecondary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
            }

            let upcoming = clubEvents.filter { $0.date > Date() }
            if upcoming.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 30))
                        .foregroundColor(GQColors.textTertiary)
                    Text("No upcoming events")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(GQColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            } else {
                ForEach(upcoming) { event in
                    ClubEventCard(event: event, userId: profile.id, modelContext: modelContext)
                }
                .padding(.horizontal, 16)
            }

            let past = clubEvents.filter { $0.date <= Date() }
            if !past.isEmpty {
                Text("PAST EVENTS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(GQColors.textTertiary)
                    .tracking(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                ForEach(past.reversed().prefix(5)) { event in
                    ClubEventCard(event: event, userId: profile.id, modelContext: modelContext)
                        .opacity(0.6)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Feed Section

    @ViewBuilder
    private var clubFeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if posts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(GQGradients.primary.opacity(0.7))
                    Text("No posts yet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                    Text("Be the first to share something!")
                        .font(.system(size: 12))
                        .foregroundColor(GQColors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .homeSocialCard(cornerRadius: 14)
                .padding(.horizontal, 16)
            } else {
                ForEach(posts) { post in
                    ClubPostCard(post: post, currentUserId: profile.id)
                }
            }
        }
    }

    // MARK: - Leaderboard Section

    @ViewBuilder
    private var clubLeaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("THIS WEEK")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(GQColors.textTertiary)
                .tracking(1)
                .padding(.horizontal, 16)

            ForEach(Array(leaderboardData.enumerated()), id: \.offset) { index, entry in
                HStack(spacing: 12) {
                    Text("#\(index + 1)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(medalColor(for: index))
                        .frame(width: 32)

                    Circle()
                        .fill(GQGradients.primary)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(String(entry.name.prefix(1)))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text("\(entry.sets) sets")
                            .font(.system(size: 12))
                            .foregroundColor(GQColors.textTertiary)
                    }

                    Spacer()

                    Text("\(entry.points) pts")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(GQColors.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(index < 3 ? GQColors.adaptiveOverlay(0.03) : Color.clear)
                .cornerRadius(10)
            }

            // Exercise Leaderboard link
            NavigationLink {
                LeaderboardView(clubId: club.id)
            } label: {
                HStack {
                    Image(systemName: "trophy.fill")
                        .foregroundColor(GQColors.textSecondary)
                    Text("Exercise Leaderboard")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(GQColors.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(GQColors.adaptiveOverlay(0.05))
                .cornerRadius(12)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Members Section

    @ViewBuilder
    private var clubMembersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(club.memberCount) MEMBERS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(GQColors.textTertiary)
                    .tracking(1)

                Spacer()

                Button {
                    withAnimation { showPartnerOnly.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showPartnerOnly ? "person.2.fill" : "person.2")
                            .font(.system(size: 11))
                        Text("Looking for Partner")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(showPartnerOnly ? GQColors.textSecondary : .gray)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(showPartnerOnly ? GQColors.textSecondary.opacity(0.15) : GQColors.adaptiveOverlay(0.04))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)

            let displayed = showPartnerOnly
                ? memberData.filter { $0.lookingForPartner }
                : memberData

            ForEach(displayed, id: \.name) { member in
                HStack(spacing: 12) {
                    Circle()
                        .fill(GQGradients.primary)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(String(member.name.prefix(1)))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)

                        HStack(spacing: 6) {
                            Text(member.role)
                                .font(.system(size: 12))
                                .foregroundColor(GQColors.textTertiary)

                            if member.lookingForPartner {
                                Text("Looking for partner")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(GQColors.textSecondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(GQColors.textSecondary.opacity(0.15))
                                    .cornerRadius(4)
                            }
                        }
                    }

                    Spacer()

                    if member.isOnline {
                        Circle()
                            .fill(GQColors.textSecondary)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .contextMenu {
                    if member.id != profile.id {
                        // Admin actions (admins can remove members and promote)
                        if club.adminIds.contains(profile.id) && club.creatorId != member.id {
                            Button {
                                do {
                                    try ClubService.shared.removeMember(clubId: club.id, userId: member.id, adminId: profile.id)
                                } catch {
                                    clubServiceError = error.localizedDescription
                                    showClubServiceError = true
                                }
                            } label: {
                                Label("Remove Member", systemImage: "person.badge.minus")
                            }

                            if !club.adminIds.contains(member.id) {
                                Button {
                                    do {
                                        try ClubService.shared.promoteToAdmin(clubId: club.id, userId: member.id, adminId: profile.id)
                                    } catch {
                                        clubServiceError = error.localizedDescription
                                        showClubServiceError = true
                                    }
                                } label: {
                                    Label("Promote to Admin", systemImage: "star")
                                }
                            }
                        }

                        // Owner-only: transfer ownership
                        if club.creatorId == profile.id {
                            Button {
                                do {
                                    try ClubService.shared.transferOwnership(clubId: club.id, newOwnerId: member.id, currentOwnerId: profile.id)
                                } catch {
                                    clubServiceError = error.localizedDescription
                                    showClubServiceError = true
                                }
                            } label: {
                                Label("Transfer Ownership", systemImage: "arrow.right.arrow.left")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data

    private var leaderboardData: [(name: String, sets: Int, workouts: Int, points: Int)] {
        let users = SocialSeeder.fakeUsers
        return club.memberIds.compactMap { memberId in
            guard let user = users.first(where: { $0.id == memberId }) else { return nil }
            // Deterministic stats from UUID hash
            let hash = abs(memberId.hashValue)
            let sets = 20 + (hash % 30)
            let workouts = 2 + (hash % 5)
            let points = sets * 5
            return (name: user.name, sets: sets, workouts: workouts, points: points)
        }
        .sorted { $0.points > $1.points }
    }

    private var memberData: [(id: UUID, name: String, role: String, isOnline: Bool, lookingForPartner: Bool)] {
        let users = SocialSeeder.fakeUsers
        return club.memberIds.compactMap { memberId in
            guard let user = users.first(where: { $0.id == memberId }) else { return nil }
            let membership = memberships.first(where: { $0.userId == memberId })
            let role = membership?.role ?? .member
            let hash = abs(memberId.hashValue)
            let isOnline = hash % 3 != 0
            let lookingForPartner = membership?.workoutPartnerStatus == .available
            return (id: memberId, name: user.name, role: role.rawValue.capitalized, isOnline: isOnline, lookingForPartner: lookingForPartner)
        }
    }

    private func medalColor(for index: Int) -> Color {
        switch index {
        case 0: return GQColors.textSecondary
        case 1: return Color(white: 0.75)
        case 2: return GQColors.textSecondary
        default: return GQColors.textTertiary
        }
    }

    private func leaveClub() {
        do {
            try ClubService.shared.leaveClub(clubId: club.id, userId: profile.id)
            dismiss()
        } catch {
            clubServiceError = error.localizedDescription
            showClubServiceError = true
        }
    }
}

// MARK: - Club Post Card

struct ClubPostCard: View {
    let post: ClubPost
    let currentUserId: UUID?
    @State private var liked: Bool = false

    init(post: ClubPost, currentUserId: UUID? = nil) {
        self.post = post
        self.currentUserId = currentUserId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(GQGradients.primary)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(post.authorName.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorName)
                        .font(.system(size: 14, weight: .semibold))
                    Text(post.timestamp.timeAgoDisplay())
                        .font(.system(size: 11))
                        .foregroundColor(GQColors.textTertiary)
                }

                Spacer()

                // Post type badge
                HStack(spacing: 4) {
                    Image(systemName: post.postType.icon)
                        .font(.system(size: 10))
                    Text(post.postType.rawValue)
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(GQColors.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(GQColors.textSecondary.opacity(0.15))
                .cornerRadius(6)
            }

            // Content
            Text(post.content)
                .font(.system(size: 14))
                .foregroundColor(GQColors.textPrimary)

            // Actions
            HStack(spacing: 20) {
                Button {
                    liked.toggle()
                    post.likeCount += liked ? 1 : -1
                    #if canImport(UIKit)
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    #endif
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: liked ? "heart.fill" : "heart")
                        if post.likeCount > 0 {
                            Text("\(post.likeCount)")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundColor(liked ? GQColors.deepBlue : GQColors.textTertiary)
                }

                Button {
                    // Comment
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                        if post.commentCount > 0 {
                            Text("\(post.commentCount)")
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textTertiary)
                }

                Spacer()

                // Copy-to-Train surfaces only for posts that carry a workout
                // AND when we know who the current viewer is AND it's not
                // their own post (no self-copy).
                if let workoutId = post.workoutId,
                   let uid = currentUserId,
                   post.authorId != uid {
                    let _ = workoutId  // referenced for future Train-view hydration
                    CopyToTrainButton(postId: post.id, userId: uid)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(GQColors.adaptiveOverlay(0.04))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }
}

// MARK: - New Club Post Sheet

struct NewClubPostSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let club: Club
    let profile: UserProfile

    @State private var content = ""
    @State private var postType: ClubPostType = .general

    var body: some View {
        NavigationStack {
            Form {
                Section("Post Type") {
                    Picker("Type", selection: $postType) {
                        ForEach(ClubPostType.allCases, id: \.self) { type in
                            Label(type.rawValue, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                }

                Section("What's on your mind?") {
                    TextField("Share with the club...", text: $content, axis: .vertical)
                        .lineLimit(4...10)
                }
            }
            .navigationTitle("New Post")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        createPost()
                    }
                    .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func createPost() {
        let post = ClubPost(
            clubId: club.id,
            authorId: profile.id,
            authorName: profile.name,
            authorUsername: profile.username,
            postType: postType,
            content: content
        )
        modelContext.insert(post)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Club Map sheet

/// Full-screen map for browsing clubs + events by location. Club pins use
/// the app-gradient monogram style; event pins are calendar-tiles tinted
/// amber so they pop against club pins. Tapping a pin shows an overlay
/// card with quick-action buttons.
struct ClubMapView: View {
    let clubs: [Club]
    let events: [ClubEvent]
    let profile: UserProfile
    let selectedClub: (Club) -> Void
    let selectedEvent: (ClubEvent) -> Void

    @State private var selectedPin: MapPin? = nil
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 44.225, longitude: -76.490),
        span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
    ))
    @State private var showEvents: Bool = true
    @State private var showClubs: Bool = true

    enum MapPin: Hashable, Identifiable {
        case club(Club)
        case event(ClubEvent, coord: CLLocationCoordinate2D)

        var id: String {
            switch self {
            case .club(let c): return "club-\(c.id.uuidString)"
            case .event(let e, _): return "event-\(e.id.uuidString)"
            }
        }

        static func == (lhs: MapPin, rhs: MapPin) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    /// Deterministic jitter for clubs without hard coords — spreads
    /// them around the Kingston center instead of stacking on one pin.
    private func fallbackCoord(for club: Club) -> CLLocationCoordinate2D {
        let seed = abs(club.id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        let jitterLat = Double((seed % 60) - 30) / 3500.0   // ±~0.009°
        let jitterLon = Double(((seed / 60) % 60) - 30) / 3500.0
        return CLLocationCoordinate2D(latitude: 44.225 + jitterLat, longitude: -76.490 + jitterLon)
    }

    /// Coord for a club — real lat/lon if present, else a fallback
    /// jitter around the city center so every club renders a pin.
    /// Clubs without any location signal (neither coords nor location
    /// string) are filtered out upstream.
    private func resolvedCoord(_ club: Club) -> CLLocationCoordinate2D {
        if let lat = club.latitude, let lon = club.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return fallbackCoord(for: club)
    }

    private var mappableClubs: [Club] {
        clubs.filter { $0.latitude != nil || ($0.location.map { !$0.isEmpty } ?? false) }
    }

    /// Events with coordinates resolved from their parent club.
    private var eventsWithCoords: [(event: ClubEvent, coord: CLLocationCoordinate2D)] {
        events.compactMap { e in
            guard let club = clubs.first(where: { $0.id == e.clubId }) else { return nil }
            guard club.latitude != nil || (club.location.map { !$0.isEmpty } ?? false) else { return nil }
            return (e, resolvedCoord(club))
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                if showClubs {
                    ForEach(mappableClubs) { club in
                        Annotation(club.name, coordinate: resolvedCoord(club)) {
                            clubPin(club)
                        }
                    }
                }
                if showEvents {
                    ForEach(Array(eventsWithCoords.enumerated()), id: \.element.event.id) { _, item in
                        Annotation(item.event.title, coordinate: item.coord) {
                            eventPin(item.event)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .ignoresSafeArea(edges: .bottom)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { selectedPin = nil }
            }

            // Top-right filter toggles — show/hide clubs vs events
            VStack(alignment: .trailing, spacing: 8) {
                filterToggle(label: "Clubs", systemImage: "person.3.fill", on: $showClubs)
                filterToggle(label: "Events", systemImage: "calendar", on: $showEvents)
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: 44.225, longitude: -76.490),
                            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
                        ))
                    }
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .padding(10)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

            if let pin = selectedPin {
                pinOverlay(pin)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 24)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedPin?.id)
    }

    // MARK: - Pins

    @ViewBuilder
    private func clubPin(_ club: Club) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedPin = .club(club) }
        } label: {
            let initial = String(club.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
            ZStack {
                Circle()
                    .fill(GQGradients.primary)
                    .frame(width: 34, height: 34)
                Text(initial)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func eventPin(_ event: ClubEvent) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedPin = .event(event, coord: CLLocationCoordinate2D()) }
        } label: {
            let day = Calendar.current.component(.day, from: event.date)
            VStack(spacing: 0) {
                Image(systemName: "calendar")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                Text("\(day)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(GQColors.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 30, height: 34)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter toggles

    @ViewBuilder
    private func filterToggle(label: String, systemImage: String, on: Binding<Bool>) -> some View {
        Button {
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            on.wrappedValue.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(on.wrappedValue ? .white : GQColors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(on.wrappedValue
                    ? AnyShapeStyle(GQGradients.primary)
                    : AnyShapeStyle(.ultraThinMaterial))
            )
            .overlay(
                Capsule().stroke(
                    on.wrappedValue ? Color.clear : Color.white.opacity(0.25),
                    lineWidth: 1
                )
            )
            .opacity(on.wrappedValue ? 1.0 : 0.85)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Overlay card

    @ViewBuilder
    private func pinOverlay(_ pin: MapPin) -> some View {
        switch pin {
        case .club(let club):
            clubOverlayCard(club)
        case .event(let event, _):
            eventOverlayCard(event)
        }
    }

    @ViewBuilder
    private func clubOverlayCard(_ club: Club) -> some View {
        let isMember = club.memberIds.contains(profile.id)
        HStack(spacing: 12) {
            ClubMonogramAvatar(club: club, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(club.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    if club.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(GQGradients.primary)
                    }
                }
                HStack(spacing: 6) {
                    if let loc = club.location {
                        Text(loc).font(.system(size: 11))
                    }
                    Text("·").font(.system(size: 10))
                    Text("\(club.memberCount) members").font(.system(size: 11))
                }
                .foregroundColor(GQColors.textTertiary)
            }
            Spacer(minLength: 8)
            Button { selectedClub(club) } label: {
                Text(isMember ? "Open" : "View")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(GQGradients.primary))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private static let eventMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    @ViewBuilder
    private func eventOverlayCard(_ event: ClubEvent) -> some View {
        let day = Calendar.current.component(.day, from: event.date)
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(Self.eventMonthFormatter.string(from: event.date).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                Text("\(day)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(GQColors.textPrimary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 44, height: 44)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                Text("\(event.date.formatted(date: .omitted, time: .shortened))\((event.location ?? "").isEmpty ? "" : " · \(event.location ?? "")")")
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button { selectedEvent(event) } label: {
                Text("Open")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(GQGradients.primary))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Grouped card container (inset white section)

private struct GroupedCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .background(GQColors.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(GQColors.borderDefault.opacity(0.45), lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
    }
}

extension View {
    /// Wraps a section in an inset white rounded card with a subtle
    /// border — matches Apple's grouped list style.
    func groupedCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(GroupedCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Shared label style for compact meta rows

/// Tight icon+text label used on overlay chrome. Keeps the icon visually
/// aligned with the text baseline and drops the default padding.
struct CompactMetaLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 9, weight: .semibold))
            configuration.title
        }
    }
}

// MARK: - Club cover image

/// Cover photo for featured/hero cards. Uses club.imageData when present,
/// otherwise pulls a deterministic Unsplash fitness photo keyed by the
/// club's ID. Shows the fallback gradient while loading so the card never
/// flashes empty.
struct ClubCoverImage: View {
    let club: Club
    let fallbackGradient: LinearGradient

    @State private var remoteData: Data? = nil

    var body: some View {
        ZStack {
            #if canImport(UIKit)
            if let data = club.imageData ?? remoteData, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                fallbackGradient
            }
            #else
            fallbackGradient
            #endif
        }
        .task(id: club.id) {
            guard club.imageData == nil, remoteData == nil else { return }
            let idx = abs(club.id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
            let photoId = UnsplashPhotoService.photoId(forIndex: idx)
            if let data = await UnsplashPhotoService.fetch(id: photoId) {
                await MainActor.run { remoteData = data }
            }
        }
    }
}

// MARK: - Shared club monogram avatar

/// Per-club fallback avatar — first letter on a deterministic gradient
/// pulled from a curated palette. Gives every club a distinct identity
/// so the list doesn't read as a wall of identical dumbbell icons.
struct ClubMonogramAvatar: View {
    let club: Club
    let size: CGFloat

    var body: some View {
        let initial = String(club.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
        Circle()
            .fill(GQGradients.primary)
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            )
    }
}
