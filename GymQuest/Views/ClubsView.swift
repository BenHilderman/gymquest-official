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

        // Extra discovery data — idempotent on a sentinel-club name so
        // re-running the app doesn't duplicate. Gives Discover content
        // to show on installs where the user has already been seeded
        // as a member of every original club.
        let sentinelName = "Kingston Strength Collective"
        let sentinelDescriptor = FetchDescriptor<Club>(predicate: #Predicate { $0.name == sentinelName })
        if ((try? modelContext.fetchCount(sentinelDescriptor)) ?? 0) == 0 {
            seedDemoDiscovery(modelContext: modelContext, userId: userId, users: users)
        }

        try? modelContext.save()
    }

    /// Second-wave seed: ~10 extra clubs the user is NOT a member of,
    /// clustered near Kingston with varied categories + member counts,
    /// plus a batch of upcoming events so UPCOMING NEAR YOU / POPULAR
    /// NEAR YOU actually have content on demo devices.
    private static func seedDemoDiscovery(modelContext: ModelContext, userId: UUID, users: [(id: UUID, name: String, username: String)]) {
        let cal = Calendar.current
        let now = Date()

        // Each tuple: (name, description, lat, lon, memberCount, category, tags, verified)
        let seeds: [(name: String, desc: String, lat: Double, lon: Double, members: Int, category: ClubCategory, tags: [String], verified: Bool)] = [
            ("Kingston Strength Collective", "Morning lifting sessions, barbell-focused. Coaches available Tue + Thu.", 44.2275, -76.4910, 312, .weightlifting, ["strength", "kingston", "barbell"], true),
            ("Limestone CrossFit",            "AMRAP + WOD every weekday 6am & 5:30pm. Drop-ins welcome.",                  44.2310, -76.4850, 248, .crossfit, ["crossfit", "kingston"], true),
            ("Queen's Climbing Club",         "Indoor + outdoor sessions. Beginner nights Wednesdays.",                      44.2245, -76.4995, 184, .climbing, ["climbing", "queens"], false),
            ("Frontenac Trail Runners",       "Off-road group runs — Lemoine Point, K&P Trail, Gould Lake.",                44.2390, -76.5200, 139, .running, ["trail", "kingston"], false),
            ("Kingston Swim Squad",           "Lap swimming + open-water sessions in summer. All abilities.",                44.2188, -76.4892, 97,  .swimming, ["swim", "kingston"], true),
            ("ARC Yoga & Mobility",           "Midday mobility flows. 30-min sessions, just roll in.",                       44.2266, -76.4956, 221, .yoga, ["yoga", "mobility", "queens"], false),
            ("Cataraqui Calisthenics",        "Bodyweight training in the park when it's warm, ARC when it's not.",          44.2360, -76.5080, 78,  .generalFitness, ["calisthenics", "bodyweight"], false),
            ("Kingston Triathlon Club",       "Swim/bike/run. Race prep + shared long rides every Saturday.",                44.2210, -76.4880, 112, .running, ["triathlon", "endurance"], true),
            ("HIIT Nights Kingston",          "45-min HIIT sessions Mon/Wed/Fri at 7pm. Partner-friendly.",                  44.2289, -76.4821, 165, .hiit, ["hiit", "kingston"], false),
            ("Queens Boxing & Kickboxing",    "Pad work, bag rounds, technique. No sparring required.",                      44.2265, -76.4932, 142, .martialArts, ["boxing", "queens"], false)
        ]

        var created: [Club] = []
        for s in seeds {
            let club = Club(
                name: s.name,
                clubDescription: s.desc,
                location: "Kingston, ON",
                latitude: s.lat,
                longitude: s.lon,
                creatorId: users[(created.count + 2) % users.count].id,
                memberIds: Array(users.shuffled().prefix(Int.random(in: 3...7)).map(\.id)),  // user NOT included
                joinType: .open,
                memberCount: s.members,
                isVerified: s.verified,
                tags: s.tags,
                createdAt: cal.date(byAdding: .day, value: -Int.random(in: 5...180), to: now) ?? now,
                category: s.category,
                lastActivityDate: cal.date(byAdding: .minute, value: -Int.random(in: 5...600), to: now),
                isListedInDiscovery: true
            )
            modelContext.insert(club)
            created.append(club)
        }

        // Memberships so live-count logic has someone to count
        for club in created {
            for (i, memberId) in club.memberIds.enumerated() {
                let m = ClubMembership(
                    userId: memberId,
                    clubId: club.id,
                    role: i == 0 ? .admin : .member,
                    workoutPartnerStatus: .notLooking
                )
                modelContext.insert(m)
            }
        }

        // Upcoming events spread across the next 10 days at varied times
        // so Popular/Upcoming sections have live-feeling content.
        struct EventSeed {
            let club: Club
            let title: String
            let description: String
            let location: String
            let dayOffset: Int
            let hour: Int
            let minute: Int
            let durationHours: Double
            let attendees: Int
            let type: ClubEventType
        }

        let evSeeds: [EventSeed] = [
            EventSeed(club: created[0], title: "Heavy Squat Night",         description: "Work up to a heavy triple. Spotters provided.",      location: "The ARC - Platform Area",     dayOffset: 0, hour: 18, minute: 0,  durationHours: 1.5, attendees: 11, type: .workout),
            EventSeed(club: created[1], title: "Friday Murph",              description: "Partner scaling available. Finishers get a patch.",  location: "Limestone CrossFit Box",      dayOffset: 1, hour: 6,  minute: 0,  durationHours: 1.0, attendees: 18, type: .competition),
            EventSeed(club: created[2], title: "Beginner Climb Night",      description: "Intro to top-rope. Rentals included.",               location: "Boiler Room Climbing Gym",    dayOffset: 1, hour: 19, minute: 0,  durationHours: 2.0, attendees: 14, type: .meetup),
            EventSeed(club: created[3], title: "Sunrise K&P Trail Run",     description: "8K easy pace on the K&P Trail.",                      location: "K&P Trailhead",                dayOffset: 2, hour: 7,  minute: 0,  durationHours: 1.25, attendees: 9,  type: .groupRun),
            EventSeed(club: created[4], title: "Thursday Lane Swim",        description: "1,500m main set, lanes by pace.",                    location: "Artillery Park Aquatic Ctr",  dayOffset: 2, hour: 17, minute: 30, durationHours: 1.0, attendees: 7,  type: .practice),
            EventSeed(club: created[5], title: "Lunch Mobility Flow",       description: "30-min hip + shoulder mobility flow.",               location: "ARC Studio 2",                dayOffset: 0, hour: 12, minute: 15, durationHours: 0.5, attendees: 22, type: .practice),
            EventSeed(club: created[6], title: "City Park Calisthenics",    description: "Pull-ups, dips, muscle-ups. Beginner regressions.", location: "City Park Bars",              dayOffset: 3, hour: 10, minute: 0,  durationHours: 1.25, attendees: 8,  type: .workout),
            EventSeed(club: created[7], title: "Long Ride — Wolfe Island",  description: "70K ride to Wolfe Island and back. Cafe stop.",     location: "Kingston Ferry Terminal",     dayOffset: 4, hour: 8,  minute: 0,  durationHours: 4.0, attendees: 6,  type: .groupRide),
            EventSeed(club: created[8], title: "Partner HIIT Night",        description: "10 rounds, partner-swap AMRAP style.",               location: "ARC Functional Area",         dayOffset: 0, hour: 19, minute: 0,  durationHours: 0.75, attendees: 16, type: .workout),
            EventSeed(club: created[9], title: "Saturday Pad Work",         description: "Technique-focused pad rounds. All levels.",          location: "ARC Combat Room",             dayOffset: 5, hour: 11, minute: 0,  durationHours: 1.5, attendees: 12, type: .practice),
            EventSeed(club: created[0], title: "Sunday Back-Off Day",       description: "Light speed work + accessories. Low intensity.",     location: "The ARC - Platform Area",     dayOffset: 6, hour: 10, minute: 0,  durationHours: 1.0, attendees: 10, type: .workout),
            EventSeed(club: created[1], title: "Open Gym",                  description: "Bring your own programming. Coach on deck.",         location: "Limestone CrossFit Box",      dayOffset: 7, hour: 17, minute: 30, durationHours: 1.5, attendees: 9,  type: .workout),
        ]

        for s in evSeeds {
            let start = cal.date(byAdding: .day, value: s.dayOffset, to: cal.startOfDay(for: now))!
                .addingTimeInterval(TimeInterval(s.hour * 3600 + s.minute * 60))
            let end = start.addingTimeInterval(s.durationHours * 3600)
            let attendeeIds = Array(users.shuffled().prefix(s.attendees).map(\.id))
            let event = ClubEvent(
                clubId: s.club.id,
                creatorId: s.club.creatorId,
                creatorName: users.first(where: { $0.id == s.club.creatorId })?.name ?? "",
                title: s.title,
                eventDescription: s.description,
                location: s.location,
                date: start,
                endDate: end,
                maxAttendees: max(s.attendees + 4, 20),
                attendeeIds: attendeeIds,
                eventType: s.type
            )
            modelContext.insert(event)
        }
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
    case watch = "Watch"
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

/// Intention-based discovery lens. Sort/filter *by* the user's actual
/// question of the moment ("what's close?" / "what's tonight?") instead
/// of by broad category. Selected lens drives the Discover top pick,
/// result-count header, and ordering of the rich-card list.
enum DiscoverLens: String, CaseIterable, Identifiable {
    case closest, upcoming, busiest, friends, fresh
    var id: String { rawValue }
    var label: String {
        switch self {
        case .closest:  return "Closest"
        case .upcoming: return "Upcoming"
        case .busiest:  return "Busiest"
        case .friends:  return "Friends in"
        case .fresh:    return "New"
        }
    }
    var icon: String {
        switch self {
        case .closest:  return "location.fill"
        case .upcoming: return "calendar"
        case .busiest:  return "flame.fill"
        case .friends:  return "person.2.fill"
        case .fresh:    return "sparkles"
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
    @Query private var allFollowsForAlive: [Friend]

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
    @State private var discoverLens: DiscoverLens = .closest
    @State private var selectedVibeFilter: String? = nil
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

    // MARK: - Toolbar (shared between List + Map modes)

    /// List ⇄ Map segment in the principal slot replaces the static
    /// "Clubs" title. Trailing slot keeps the search + create buttons.
    @ToolbarContentBuilder
    private var sharedToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: $clubViewMode) {
                Image(systemName: "list.bullet").tag(ClubViewMode.list)
                Image(systemName: "map").tag(ClubViewMode.map)
                Image(systemName: "play.rectangle.fill").tag(ClubViewMode.watch)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
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

    // MARK: - Body

    var body: some View {
        Group {
            switch clubViewMode {
            case .map:
                ClubsMapMode(
                    clubs: topLevelClubs,
                    events: allEvents,
                    profile: profile,
                    userClubIds: Set(yourClubs.map(\.id)),
                    liveCount: { liveCount(for: $0) },
                    nextEventFor: { nextEvent(for: $0) },
                    friendsInClub: { friendsInClub($0) },
                    firstFriendName: { firstFriendNameInClub($0) },
                    distanceString: { distanceString(for: $0) },
                    recentPost: { mostRecentPost(for: $0) },
                    onSelectClub: { selectedClub = $0 }
                )
                .toolbar { sharedToolbar }
                .sheet(isPresented: $showingCreateClub) {
                    CreateClubSheet(profile: profile)
                }
                .sheet(isPresented: $presentingSearch) {
                    clubSearchSheet
                }
                .navigationDestination(item: $selectedClub) { club in
                    ClubDetailView(club: club, profile: profile)
                }
                .navigationDestination(item: $selectedEvent) { event in
                    if let club = allClubs.first(where: { $0.id == event.clubId }) {
                        ClubDetailView(club: club, profile: profile)
                    }
                }
            case .watch:
                ClubsWatchMode(
                    allClubs: topLevelClubs,
                    userClubIds: Set(yourClubs.map(\.id)),
                    posts: allClubPosts,
                    events: allEvents,
                    profile: profile,
                    nextEventFor: { nextEvent(for: $0) },
                    friendsInClub: { friendsInClub($0) },
                    distanceString: { distanceString(for: $0) },
                    onSelectClub: { selectedClub = $0 }
                )
                .toolbar { sharedToolbar }
                .navigationDestination(item: $selectedClub) { club in
                    ClubDetailView(club: club, profile: profile)
                }
            case .list:
                listModeBody
            }
        }
    }

    /// Original list body, refactored out so map mode can swap in. The
    /// scroll view + LazyVStack with the pinned filter strip lives here.
    /// Alive Phase 1 — ambient header strip pinned at the top of the Clubs
    /// list. "N friends · M clubmates lifting now" + tiny avatar peek.
    private var aliveAmbientStrip: some View {
        let now = Date()
        let followedIds = Set(allFollowsForAlive.filter { $0.userId == profile.id }.map(\.odId))
        let myClubIds = Set(allClubs.filter { $0.memberIds.contains(profile.id) }.map(\.id))
        let clubmateIds = Set(allClubs
            .filter { myClubIds.contains($0.id) }
            .flatMap { $0.memberIds })
            .subtracting([profile.id])
        let liveFriendIds = presenceStates
            .filter { followedIds.contains($0.userId) && Self.isLiveForAlive($0, now: now) }
            .map(\.userId)
        let liveClubmateIds = presenceStates
            .filter { clubmateIds.contains($0.userId) && Self.isLiveForAlive($0, now: now) }
            .map(\.userId)
        return AmbientHeaderStrip(
            friendCount: liveFriendIds.count,
            clubmateCount: liveClubmateIds.count,
            avatarPeek: Array((liveFriendIds + liveClubmateIds).prefix(3))
        )
    }

    private static func isLiveForAlive(_ s: UserPresenceState, now: Date) -> Bool {
        switch s.status {
        case .arriving, .training, .resting: break
        default: return false
        }
        if let started = s.startedAt, now.timeIntervalSince(started) > 3 * 3600 { return false }
        return true
    }

    private var listModeBody: some View {
        ScrollView {
            // pinnedViews: [.sectionHeaders] makes the filter strip
            // stick to the top of the scroll view as the user scrolls
            // past it — same pattern Discover uses.
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                // Removed: aliveAmbientStrip. The liveActivityHeader below
                // already surfaces live presence + co-presence at the top
                // of the list — doubling up was redundant.

                // R4 — NOW ticker + co-presence banner. Auto-rotating
                // strip of recent training presence + posts from your
                // clubs. Co-presence banner appears when a friend is
                // training in a club you're in. Both hide gracefully
                // when there's no signal.
                liveActivityHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                // New Clubs hero stack — tonight event hero + training-now
                // status row. Lifted from the Clubs reference design.
                // Shown above the pinned filter strip so they sit at the
                // very top of the page.
                if let nextEvent = nextEventInMyClubs {
                    tonightHeroCard(event: nextEvent)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                }

                if !sortedYourClubs.isEmpty {
                    trainingNowSection
                        .padding(.top, 18)
                }

                Section {
                    if !computedEventRows.isEmpty {
                        groupedSection(header: "Tonight & This Week", icon: "calendar") {
                            eventsRowsOnly
                        }
                        .padding(.top, 16)
                    }

                    if hasAnyDiscoverContent {
                        groupedSection(
                            header: "Nearby",
                            icon: "location.fill"
                        ) {
                            discoverCardContent
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                    }

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
                } header: {
                    pinnedFilterStrip
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(GQColors.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(GQColors.background, for: .navigationBar)
        .toolbar { sharedToolbar }
        .refreshable {
            try? await Task.sleep(for: .milliseconds(300))
        }
        .onAppear {
            ClubSeeder.seedIfNeeded(modelContext: modelContext, userId: profile.id)
            try? ClubService.shared.evaluateClubHealth()
            // Refresh demo presence so the NOW ticker + co-presence
            // banner have live data (3 fake users training right now).
            PresenceSeeder.refreshDemoPresence(in: modelContext)
            // R5.5 — seed a couple of word-of-mouth attributions so the
            // "Marcus shared this" surface renders out of the box.
            SharedClubStore.seedIfNeeded(
                allClubs: topLevelClubs,
                userClubIds: Set(yourClubs.map(\.id))
            )
            // R7+ — seed procedural photo + video posts on non-joined
            // clubs so the media-first surfaces always have content.
            ClubMediaSeeder.seedIfNeeded(
                modelContext: modelContext,
                allClubs: topLevelClubs,
                userClubIds: Set(yourClubs.map(\.id))
            )
        }
        .sheet(isPresented: $showingCreateClub) {
            CreateClubSheet(profile: profile)
        }
        .sheet(isPresented: $presentingSearch) {
            clubSearchSheet
        }
        .sheet(isPresented: $presentingMap) {
            clubMapSheet
        }
        .navigationDestination(item: $selectedClub) { club in
            ClubDetailView(club: club, profile: profile)
        }
        .navigationDestination(item: $selectedEvent) { event in
            if let club = allClubs.first(where: { $0.id == event.clubId }) {
                ClubDetailView(club: club, profile: profile)
            }
        }
    }

    // MARK: - Tonight Hero + Training Now (Clubs reference design)

    /// Soonest upcoming event from any of the user's clubs. Drives the
    /// big purple hero card at the top of the page; nil hides it.
    private var nextEventInMyClubs: ClubEvent? { upcomingEventsInMyClubs.first }

    // MARK: - R4: NOW ticker + co-presence

    /// Stacked vertical: optional co-presence banner + NOW ticker. Both
    /// auto-hide when there's no signal so the page stays clean for
    /// quiet hours / cold-start installs.
    @ViewBuilder
    private var liveActivityHeader: some View {
        VStack(spacing: 8) {
            if let match = coPresenceMatches.first {
                coPresenceBanner(match: match)
            }
            if !nowTickerEntries.isEmpty {
                nowTickerStrip
            }
        }
    }

    private struct NowTickerEntry: Identifiable {
        let id: String
        let userInitial: String
        let userName: String
        let action: String
        let timeLabel: String
        let isLive: Bool
    }

    /// Sources for the ticker — currently-training presence + posts in
    /// your clubs from the last 30 min, capped to 5 entries. Most recent
    /// first.
    private var nowTickerEntries: [NowTickerEntry] {
        let myClubIds = Set(yourClubs.map(\.id))
        let usersById = Dictionary(uniqueKeysWithValues: SocialSeeder.fakeUsers.map { ($0.id, $0) })

        let live: [NowTickerEntry] = presenceStates
            .filter { $0.status == .training || $0.status == .resting }
            .compactMap { ps in
                guard let user = usersById[ps.userId] else { return nil }
                let firstName = user.name.split(separator: " ").first.map(String.init) ?? user.name
                let workoutLabel = ps.workoutTypeRaw?.lowercased() ?? "training"
                return NowTickerEntry(
                    id: "live-\(user.id.uuidString)",
                    userInitial: String(firstName.first ?? "?").uppercased(),
                    userName: firstName,
                    action: "is lifting · \(workoutLabel)",
                    timeLabel: "\(ps.minutesIn)m in",
                    isLive: true
                )
            }

        let cutoff = Date().addingTimeInterval(-30 * 60)
        let recentPosts: [NowTickerEntry] = allClubPosts
            .filter { myClubIds.contains($0.clubId) && $0.timestamp >= cutoff }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(5)
            .map { post in
                let firstName = post.authorName.split(separator: " ").first.map(String.init) ?? post.authorName
                let mins = max(0, Int(Date().timeIntervalSince(post.timestamp) / 60))
                return NowTickerEntry(
                    id: "post-\(post.id.uuidString)",
                    userInitial: String(firstName.first ?? "?").uppercased(),
                    userName: firstName,
                    action: "shared an update",
                    timeLabel: mins == 0 ? "just now" : "\(mins)m ago",
                    isLive: false
                )
            }

        return Array((live + recentPosts).prefix(5))
    }

    @ViewBuilder
    private var nowTickerStrip: some View {
        let entries = nowTickerEntries
        TimelineView(.periodic(from: Date(), by: 4.0)) { context in
            // Pick which entry to surface based on elapsed real time
            // — round-robin every 4 seconds.
            let idx = entries.isEmpty ? 0
                : Int(context.date.timeIntervalSinceReferenceDate / 4.0) % entries.count
            let entry = entries.indices.contains(idx) ? entries[idx] : entries.first

            if let entry {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(GQGradients.primary)
                            .frame(width: 22, height: 22)
                        Text(entry.userInitial)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                    if entry.isLive {
                        Circle().fill(GQColors.success).frame(width: 6, height: 6)
                    }
                    Text("\(entry.userName) \(entry.action)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(entry.timeLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(GQColors.textTertiary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(GQColors.surfaceBase)
                )
                .overlay(
                    Capsule().stroke(GQColors.borderDefault, lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                .id(entry.id)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity.combined(with: .move(edge: .bottom))
                ))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: entries.map(\.id))
    }

    private struct CoPresenceMatch: Identifiable {
        let id: String
        let club: Club
        let companion: String
        let companionInitial: String
        let companionUserId: UUID
        let workoutType: String
    }

    /// Demo-grade co-presence: when a friend (other club member) is
    /// currently training in a club you're in. Real implementation
    /// would correlate locations via Core Location. For now this gives
    /// the UI surface real data to render against.
    private var coPresenceMatches: [CoPresenceMatch] {
        let usersById = Dictionary(uniqueKeysWithValues: SocialSeeder.fakeUsers.map { ($0.id, $0) })
        var matches: [CoPresenceMatch] = []
        for ps in presenceStates where ps.status == .training {
            guard let user = usersById[ps.userId] else { continue }
            guard let club = yourClubs.first(where: { c in c.memberIds.contains(ps.userId) }) else { continue }
            let firstName = user.name.split(separator: " ").first.map(String.init) ?? user.name
            matches.append(CoPresenceMatch(
                id: "\(club.id.uuidString)-\(user.id.uuidString)",
                club: club,
                companion: firstName,
                companionInitial: String(firstName.first ?? "?").uppercased(),
                companionUserId: user.id,
                workoutType: ps.workoutTypeRaw ?? "training"
            ))
        }
        return matches
    }

    @ViewBuilder
    private func coPresenceBanner(match: CoPresenceMatch) -> some View {
        Button {
            selectedClub = match.club
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(GQGradients.primary)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(match.companionInitial)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .presenceRing(match.companionUserId, size: 32)
                    .reactionTarget(to: match.companionUserId, name: match.companion, from: profile.id)

                VStack(alignment: .leading, spacing: 1) {
                    Text("AT \(match.club.name.uppercased())")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(GQGradients.primary)
                        .lineLimit(1)
                    Text("\(match.companion) is training right now")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(GQGradients.primary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(GQGradients.primary.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Deep-gradient hero modeled after the Clubs reference's "TONIGHT
    /// · 7:00 PM" card: dated pill + time-remaining ring on top, club
    /// caps + big title + location + avatar stack, "I'm going" white
    /// pill + "Details" ghost button along the bottom.
    @ViewBuilder
    private func tonightHeroCard(event: ClubEvent) -> some View {
        let club = allClubs.first(where: { $0.id == event.clubId })
        let isGoing = event.attendeeIds.contains(profile.id)
        let going = max(event.attendeeIds.count, isGoing ? 1 : 0)
        let friendsGoing = friendsGoingNames(event)
        let dayLabel = relativeDayLabel(event.date).uppercased()
        let timeLabel = event.date.formatted(date: .omitted, time: .shortened)

        Button {
            selectedEvent = event
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text("\(dayLabel)  ·  \(timeLabel)")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.0)
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.28)))
                    Spacer()
                    eventTimeRing(date: event.date)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let clubName = club?.name {
                        Text(clubName.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.1)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    Text(event.title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let loc = event.location ?? club?.location {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 10, weight: .semibold))
                            Text(loc)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.78))
                    }
                }

                if going > 0 {
                    HStack(spacing: 8) {
                        avatarStack(count: min(going, 4), userIds: Array(event.attendeeIds.prefix(4)))
                        Text(goingFooter(going: going, friends: friendsGoing))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }

                if let club {
                    HStack(spacing: 6) {
                        WalkInMusicChip(track: ClubSoundtrackLibrary.warmupTrack(for: event, club: club))
                        Spacer()
                    }
                }

                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: isGoing ? "checkmark" : "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text(isGoing ? "I'm going" : "I'm going")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(GQColors.deepBlue)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.white))

                    Text("Details")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
                }

                // Alive Phase 4: "Who's going tonight" inline RSVP poll —
                // surfaces only for events on the current day. Three quick
                // taps; choice persists by toggling membership in
                // event.attendeeIds (Going) or a per-event UserDefaults
                // key for Maybe/Pass.
                if Calendar.current.isDateInToday(event.date) {
                    rsvpPollRow(event: event, isGoing: isGoing)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        GQColors.vividPurple.opacity(0.92),
                        GQColors.deepBlue.opacity(0.95),
                        Color.black.opacity(0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: GQColors.vividPurple.opacity(0.22), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    /// Alive Phase 4 — quick "Who's going tonight" RSVP for today's events.
    /// Three tap-targets; choice persists. Going flips event.attendeeIds,
    /// Maybe/Pass write a per-event UserDefaults flag. The card polls the
    /// flag on render so the user's choice sticks across sessions.
    @ViewBuilder
    private func rsvpPollRow(event: ClubEvent, isGoing: Bool) -> some View {
        HStack(spacing: 6) {
            rsvpButton(label: "Going", systemImage: "checkmark.circle.fill", active: isGoing) {
                rsvp(event: event, choice: "going")
            }
            rsvpButton(label: "Maybe", systemImage: "circle.dashed", active: rsvpChoice(eventId: event.id) == "maybe") {
                rsvp(event: event, choice: "maybe")
            }
            rsvpButton(label: "Pass", systemImage: "xmark.circle", active: rsvpChoice(eventId: event.id) == "pass") {
                rsvp(event: event, choice: "pass")
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func rsvpButton(label: String, systemImage: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(active ? GQColors.deepBlue : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(active ? Color.white.opacity(0.95) : Color.white.opacity(0.18)))
            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func rsvpChoice(eventId: UUID) -> String? {
        UserDefaults.standard.string(forKey: "alive.rsvp.\(eventId.uuidString)")
    }

    private func rsvp(event: ClubEvent, choice: String) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        UserDefaults.standard.set(choice, forKey: "alive.rsvp.\(event.id.uuidString)")
        if choice == "going" && !event.attendeeIds.contains(profile.id) {
            event.attendeeIds.append(profile.id)
            try? modelContext.save()
        }
        if choice != "going" && event.attendeeIds.contains(profile.id) {
            event.attendeeIds.removeAll { $0 == profile.id }
            try? modelContext.save()
        }
    }

    /// White ring on the right of the hero showing time-until-start.
    @ViewBuilder
    private func eventTimeRing(date: Date) -> some View {
        let total: TimeInterval = 12 * 3600 // 12-hour reference window
        let remaining = max(0, date.timeIntervalSince(Date()))
        let progress = CGFloat(min(remaining / total, 1))
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60

        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 2.5)
                .frame(width: 54, height: 54)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 54, height: 54)
            VStack(spacing: -1) {
                Text("\(hours)h")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("\(minutes)M")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
    }

    /// Generic seeded-letter avatar stack. Fed by attendee count alone
    /// since we don't reliably have profile lookups for every attendee
    /// on this surface — looks intentional rather than missing.
    @ViewBuilder
    /// Renders a stack of avatars for a known set of attendee user IDs.
    /// Each carries a `.presenceRing(...)` so any of them mid-session
    /// shows the universal Alive ring even at 22pt. Falls back to the
    /// legacy letter placeholder when fewer real IDs than the count.
    private func avatarStack(count: Int, userIds: [UUID] = []) -> some View {
        HStack(spacing: -6) {
            ForEach(0..<count, id: \.self) { i in
                let letters = ["O", "P", "K", "J"]
                let attendeeId = i < userIds.count ? userIds[i] : nil
                let initial: String = {
                    if let id = attendeeId,
                       let user = SocialSeeder.fakeUsers.first(where: { $0.id == id }) {
                        return String(user.name.prefix(1)).uppercased()
                    }
                    return letters[i % letters.count]
                }()
                Circle()
                    .fill(GQGradients.primary)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Text(initial)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                    .modifier(OptionalPresenceRing(userId: attendeeId, size: 22))
            }
        }
    }

    /// Conditional ring application. PresenceRingModifier needs a non-nil
    /// UUID; this skips the modifier entirely when no ID is available.
    private struct OptionalPresenceRing: ViewModifier {
        let userId: UUID?
        let size: CGFloat
        func body(content: Content) -> some View {
            if let userId {
                content.presenceRing(userId, size: size)
            } else {
                content
            }
        }
    }

    /// Friendly day label: "Tonight" if same day, "Tomorrow" if next,
    /// otherwise weekday short. Drives the dated pill on the hero.
    private func relativeDayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Tonight" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    /// "12 going · Olivia + Priya are in"-style line under the avatars.
    private func goingFooter(going: Int, friends: [String]) -> String {
        var pieces: [String] = []
        pieces.append("\(going) going")
        if let first = friends.first {
            if friends.count >= 2 {
                pieces.append("\(first) + \(friends[1]) are in")
            } else {
                pieces.append("\(first) is in")
            }
        }
        return pieces.joined(separator: " · ")
    }

    /// Section: green-dot caps header + horizontal scroll of clubs.
    /// Each club becomes a letter-circle avatar with a small green
    /// count badge if anyone's currently training there.
    @ViewBuilder
    private var trainingNowSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(GQColors.success)
                    .frame(width: 6, height: 6)
                Text("TRAINING NOW")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.1)
                    .foregroundColor(GQColors.textTertiary)
                Text("·  at your clubs")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(GQColors.textTertiary)
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(sortedYourClubs.prefix(8)), id: \.id) { club in
                        clubStatusCircle(club: club)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollClipDisabled()
        }
    }

    /// Letter-circle avatar with a small green count pill at the
    /// bottom-right and club name + status text below. Tapping pushes
    /// into ClubDetailView.
    @ViewBuilder
    private func clubStatusCircle(club: Club) -> some View {
        let live = liveCount(for: club)
        let initial = String(club.name.prefix(1)).uppercased()
        Button {
            selectedClub = club
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(GQGradients.primary)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Text(initial)
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        )
                    if live > 0 {
                        Text("\(live)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .padding(.horizontal, 4)
                            .background(
                                Capsule()
                                    .fill(GQColors.success)
                                    .overlay(Capsule().stroke(GQColors.background, lineWidth: 2))
                            )
                            .offset(x: 4, y: 4)
                    }
                }

                VStack(spacing: 1) {
                    Text(club.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    Text(liveSubtext(live: live))
                        .font(.system(size: 10))
                        .foregroundColor(GQColors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: 78)
        }
        .buttonStyle(.plain)
    }

    /// "3 lifting" / "1 warming up" / "quiet" — short status under the
    /// circle so the row reads at a glance like the reference.
    private func liveSubtext(live: Int) -> String {
        switch live {
        case 0: return "quiet"
        case 1: return "1 lifting"
        default: return "\(live) lifting"
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

    /// Hairline between rows inside a grouped card — native SwiftUI
    /// Divider tinted to match the Progress "Recent PRs" pattern, but
    /// a touch stronger so the separation actually reads.
    private var inRowDivider: some View {
        Divider()
            .overlay(GQColors.adaptiveOverlay(0.14))
    }

    /// Mirrors the Recent PRs card on Progress: icon + readable title
    /// ("Your Clubs", "Upcoming Events"...) at the top of a rounded
    /// white inset card, optional trailing meta text, then the rows
    /// below. Replaces the earlier tracked-caps header pattern.
    @ViewBuilder
    private func groupedSection<Content: View>(
        header: String,
        icon: String? = nil,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(GQGradients.primary)
                }
                Text(header)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11))
                        .foregroundColor(GQColors.textTertiary)
                }
            }
            .padding(.bottom, 10)

            // Hairline separating the section title from its content
            // so each section reads as a header + body, not a floating
            // label above a column.
            Rectangle()
                .fill(GQColors.borderDefault.opacity(0.6))
                .frame(height: 0.5)
                .padding(.bottom, 10)

            content()
        }
        .groupedCard()
    }

    // MARK: - Search + categories strip (top of page)

    /// Top filter strip — horizontal row of category chips + trailing
    /// Map chip. Sits directly under the nav bar with a hairline below
    /// to give the nav proper visual closure against the grouped card
    /// content that follows.
    @ViewBuilder
    private var searchAndCategoryStrip: some View {
        pinnedFilterStrip
    }

    /// Pinned header — same pattern as Discover's sticky filter bar.
    /// Scrollable category chips on the left, trailing Map pill on
    /// the right, GQColors.background to blend with the page when
    /// pinned, bottom hairline + light drop shadow for depth.
    @ViewBuilder
    private var pinnedFilterStrip: some View {
        HStack(spacing: 8) {
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
                HStack(spacing: 4) {
                    Image(systemName: "map")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Map")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(GQColors.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(GQColors.surfaceBase))
                .overlay(
                    Capsule().stroke(GQColors.borderDefault.opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(GQColors.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GQColors.borderDefault.opacity(0.55))
                .frame(height: 0.5)
        }
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
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
    /// small, centered, subtle (Apple-style footer link). Subdued
    /// blue accent rather than the full brand gradient so it doesn't
    /// compete with row content above.
    @ViewBuilder
    private func showAllRow(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(GQColors.deepBlue)
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
            clubAvatar(club, size: 44)

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
                yourClubSubtitleText(club, live: live, eventToday: eventToday)
            }

            Spacer(minLength: 8)

            yourClubTrailing(club, live: live, eventToday: eventToday)
        }
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
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(GQColors.success)
            }
        } else if eventToday, let ev = nextEvent(for: club), Calendar.current.isDateInToday(ev.date) {
            Text("Today · \(ev.date.formatted(date: .omitted, time: .shortened)) — \(ev.title)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(GQColors.textSecondary)
                .lineLimit(1)
        } else if let ev = nextEvent(for: club) {
            Text("\(eventDayLabelShort(ev.date)) · \(ev.title)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(GQColors.textSecondary)
                .lineLimit(1)
        } else {
            let friends = friendsInClub(club)
            if friends > 0, let firstName = firstFriendNameInClub(club) {
                Text(friends == 1 ? "\(firstName) is in" : "\(firstName) + \(friends - 1) friends")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(GQColors.textSecondary)
                    .lineLimit(1)
            } else {
                Text("\(club.memberCount == 1 ? "1 member" : "\(club.memberCount) members") · \(club.resolvedCategory.rawValue)")
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    /// Trailing: optional live/today badge followed by the chevron.
    /// Chevron is always present so every row reads as tappable; the
    /// count stays out of the pill because the row subtitle already
    /// says "N training now" — "3 LIVE · 3 training now" was redundant.
    @ViewBuilder
    private func yourClubTrailing(_ club: Club, live: Int, eventToday: Bool) -> some View {
        HStack(spacing: 6) {
            if live > 0 {
                Text("LIVE")
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
            }
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

    /// Compact event row — date tile + title + one combined meta line
    /// (club · time · location) + optional quiet friend-going signal.
    /// Trims the old three-line subtitle to two lines total.
    private func eventRow(_ event: ClubEvent, isJoinedClub: Bool, recommended: Bool = false) -> some View {
        let club = allClubs.first { $0.id == event.clubId }
        let isGoing = event.attendeeIds.contains(profile.id)
        let friends = friendsGoingNames(event)
        let clubName = club?.name ?? "Club"
        let timeText = event.date.formatted(date: .omitted, time: .shortened)
        let locText = event.location ?? club?.location ?? ""

        // Build one compact meta string so the row collapses to just
        // "Title" + "Meta" rather than three stacked lines.
        var metaParts: [String] = [clubName]
        metaParts.append(timeText)
        if !locText.isEmpty { metaParts.append(locText) }

        return HStack(spacing: 12) {
            eventDateTile(event.date, accent: recommended ? Color.orange : nil)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    if recommended {
                        Text("FOR YOU")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundColor(GQColors.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(GQColors.adaptiveOverlay(0.08)))
                    }
                }
                Text(metaParts.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)

                if !friends.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9, weight: .semibold))
                        Text(friendsGoingLabel(friends: friends, total: event.attendeeIds.count))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(GQColors.textSecondary)
                    .padding(.top, 1)
                }
            }

            Spacer(minLength: 8)

            if isGoing {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                    Text("GOING")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.4)
                }
                .foregroundColor(GQColors.success)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(GQColors.success.opacity(0.12)))
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

    /// "For You" picks — friends' clubs, then category match, then
    /// top-by-members. Everything draws from `searchFilteredRecommended`
    /// so the active category chip narrows the pool. When a filter is
    /// on, reasons become category-specific ("Top running", "Marcus
    /// runs too") so the For You tab clearly reflects the active chip.
    private var forYouPicks: [(club: Club, reason: String)] {
        var out: [(Club, String)] = []
        var seen = Set<UUID>()
        let catName = selectedCategory?.rawValue.lowercased()

        // 1. Friends' clubs first — strongest social pull
        for club in friendsDiscoverClubs where !seen.contains(club.id) {
            let friends = friendsInClub(club)
            let name = firstFriendNameInClub(club) ?? "A friend"
            let base = friends == 1 ? "\(name) is in" : "\(name) + \(friends - 1) friends"
            let reason: String
            if let catName {
                reason = friends == 1 ? "\(name) \(catName)s too" : "\(base) · \(catName)"
            } else {
                reason = base
            }
            out.append((club, reason))
            seen.insert(club.id)
            if out.count >= 2 { break }
        }

        // 2. Category stage
        let myCats = Set(yourClubs.map(\.resolvedCategory))
        for club in searchFilteredRecommended where !seen.contains(club.id) {
            let reason: String?
            if let cat = selectedCategory {
                // Explicit chip — label clearly so user sees the filter
                // is being honored on For You picks.
                reason = "Top \(cat.rawValue.lowercased())"
            } else if myCats.contains(club.resolvedCategory) {
                reason = "Because you \(club.resolvedCategory.rawValue.lowercased())"
            } else {
                reason = nil
            }
            if let reason {
                out.append((club, reason))
                seen.insert(club.id)
                if out.count >= 4 { break }
            }
        }

        // 3. Top-by-members fallback
        let bySize = searchFilteredRecommended.sorted { $0.memberCount > $1.memberCount }
        for club in bySize where !seen.contains(club.id) {
            let memberText = club.memberCount == 1 ? "1 member" : "\(club.memberCount) members"
            let reason = catName.map { "\($0.capitalized) · \(memberText)" } ?? memberText
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
        // Section now hosts the Discover redesign: lens hero, upcoming
        // events near you, popular clubs, map tile, by-vibe row, rich
        // list. Any of those being non-empty should surface the section,
        // not just recommended-clubs or challenges.
        !searchFilteredRecommended.isEmpty
            || !myActiveChallenges.isEmpty
            || !joinableChallenges.isEmpty
            || !upcomingEventsNearby.isEmpty
            || !clubsWithCoordinates.isEmpty
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
        .padding(.vertical, 10)
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
    /// Content of the Discover card. Intent-driven layout, prioritizing
    /// what users actually ask on this page: "what's coming up near me?"
    /// and "what's popular right now?" — both live near the top.
    @ViewBuilder
    private var discoverCardContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            discoverResultSummary
            discoverLensBar           // includes 🗺️ map button at trailing edge
            mutualEventPrompt         // R5.3 — "3 friends going to..."
            if let pick = lensedRecommendedClubs.first {
                discoverHeroCard(club: pick)
            }
            upcomingNearYouSection
            snapshotsRow              // photo evidence from non-joined clubs
            whereFriendsTrainSection  // R5.2 — clubs your friends are in
            discoverRichCardList      // header rewrites by lens (POPULAR / MORE)
        }
    }

    // MARK: - R5.2: Where your friends train

    /// Clubs the user is NOT in but at least one of their friends IS.
    /// Counted via `friendsInClub` which already does the lookup against
    /// SocialSeeder for the demo.
    private var clubsFriendsAreIn: [Club] {
        searchFilteredRecommended
            .filter { friendsInClub($0) > 0 }
            .sorted { friendsInClub($0) > friendsInClub($1) }
    }

    @ViewBuilder
    private var whereFriendsTrainSection: some View {
        let clubs = Array(clubsFriendsAreIn.prefix(8))
        if !clubs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 5) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(GQGradients.primary)
                        Text("WHERE YOUR FRIENDS TRAIN")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.1)
                            .foregroundColor(GQColors.textTertiary)
                    }
                    Spacer()
                    Text("\(clubs.count) club\(clubs.count == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(GQColors.textTertiary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(clubs, id: \.id) { club in
                            friendsTrainCard(club)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    @ViewBuilder
    private func friendsTrainCard(_ club: Club) -> some View {
        let count = friendsInClub(club)
        let firstName = firstFriendNameInClub(club) ?? ""
        let initial = String(club.name.prefix(1)).uppercased()
        let hasPost = mostRecentPost(for: club) != nil

        Button { selectedClub = club } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    if hasPost {
                        clubPostThumbnail(club, size: 110)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(GQGradients.primary)
                                .frame(width: 110, height: 110)
                            Text(initial)
                                .font(.system(size: 44, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    // Friend avatar count overlay
                    HStack(spacing: -6) {
                        ForEach(0..<min(count, 3), id: \.self) { _ in
                            Circle()
                                .fill(GQGradients.primary)
                                .frame(width: 22, height: 22)
                                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                )
                        }
                    }
                    .padding(6)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(club.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    Text(friendsTrainSubtitle(name: firstName, count: count))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(GQColors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: 130, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private func friendsTrainSubtitle(name: String, count: Int) -> String {
        if count == 0 { return "" }
        if name.isEmpty {
            return count == 1 ? "1 friend trains here" : "\(count) friends train here"
        }
        switch count {
        case 1: return "\(name) trains here"
        case 2: return "\(name) + 1 other"
        default: return "\(name) + \(count - 1) others"
        }
    }

    // MARK: - R5.3: Mutual-event prompt

    /// Top upcoming event with the most followed friends attending.
    /// Demo: counts friend overlap against SocialSeeder.fakeUsers (the
    /// shared "fake friends" pool used elsewhere). Real impl would use
    /// allFollows on the model.
    private var mutualEventPick: (event: ClubEvent, club: Club, friends: Int)? {
        let friendIds = Set(SocialSeeder.fakeUsers.prefix(6).map(\.id))
        let candidates = (upcomingEventsInMyClubs + upcomingEventsNearby)
            .compactMap { ev -> (ClubEvent, Club, Int)? in
                guard let club = allClubs.first(where: { $0.id == ev.clubId }) else { return nil }
                let count = ev.attendeeIds.filter { friendIds.contains($0) }.count
                return count >= 2 ? (ev, club, count) : nil
            }
            .sorted { $0.0.date < $1.0.date }
        return candidates.first.map { (event: $0.0, club: $0.1, friends: $0.2) }
    }

    @ViewBuilder
    private var mutualEventPrompt: some View {
        if let pick = mutualEventPick {
            Button {
                selectedEvent = pick.event
            } label: {
                HStack(spacing: 12) {
                    avatarStack(count: min(pick.friends, 3))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(pick.friends) FRIENDS GOING")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(GQGradients.primary)
                        Text("\(pick.event.title) · \(relativeDayLabel(pick.event.date))")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text("Join them")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(GQGradients.primary))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(GQGradients.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(GQGradients.primary.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Discover: upcoming near you (events)

    @ViewBuilder
    private var upcomingNearYouSection: some View {
        let events = Array(upcomingEventsNearby.prefix(8))
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                            .foregroundStyle(GQGradients.primary)
                        Text("UPCOMING NEAR YOU")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.1)
                            .foregroundColor(GQColors.textTertiary)
                    }
                    Spacer()
                    Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(GQColors.textTertiary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(events, id: \.id) { event in
                            heroEventDateCard(event)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    /// Compact date hero card — the "APR 24 / 7:00 PM" style from the
    /// Clubs reference. Tap pushes ClubDetailView for the hosting club.
    @ViewBuilder
    private func heroEventDateCard(_ event: ClubEvent) -> some View {
        let club = allClubs.first(where: { $0.id == event.clubId })
        let monthLabel = event.date.formatted(.dateTime.month(.abbreviated)).uppercased()
        let dayLabel = String(Calendar.current.component(.day, from: event.date))
        let timeLabel = event.date.formatted(date: .omitted, time: .shortened)
        let going = event.attendeeIds.count

        Button {
            selectedEvent = event
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(monthLabel)
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(.white.opacity(0.75))
                        Text(dayLabel)
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Text(timeLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.28)))
                }

                Spacer(minLength: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(club?.name ?? "")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)
                }

                if going > 0 {
                    HStack(spacing: 6) {
                        avatarStack(count: min(going, 3))
                        Text("\(going) going")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }

                if let club {
                    WalkInMusicChip(track: ClubSoundtrackLibrary.warmupTrack(for: event, club: club))
                }
            }
            .padding(14)
            .frame(width: 200, height: 210, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [
                        GQColors.vividPurple.opacity(0.9),
                        GQColors.deepBlue.opacity(0.95),
                        Color.black.opacity(0.5)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: GQColors.vividPurple.opacity(0.18), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Discover: popular near me

    /// Nearby clubs ranked by live activity first, then proximity, then
    /// member count. Limited to clubs with at least some activity or a
    /// meaningful member base so the section stays high-signal.
    private var popularNearMeClubs: [Club] {
        searchFilteredRecommended
            .filter { liveCount(for: $0) > 0 || $0.memberCount >= 15 }
            .sorted { a, b in
                let la = liveCount(for: a), lb = liveCount(for: b)
                if la != lb { return la > lb }
                let da: Double = {
                    guard let lat = a.latitude, let lon = a.longitude else { return .infinity }
                    return distanceKm(lat: lat, lon: lon)
                }()
                let db: Double = {
                    guard let lat = b.latitude, let lon = b.longitude else { return .infinity }
                    return distanceKm(lat: lat, lon: lon)
                }()
                if da != db { return da < db }
                return a.memberCount > b.memberCount
            }
    }

    @ViewBuilder
    private var popularNearMeSection: some View {
        let clubs = Array(popularNearMeClubs.prefix(4))
        if !clubs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(GQGradients.primary)
                        Text("POPULAR NEAR YOU")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.1)
                            .foregroundColor(GQColors.textTertiary)
                    }
                    Spacer()
                    let activeCount = clubs.filter { liveCount(for: $0) > 0 }.count
                    if activeCount > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(GQColors.success).frame(width: 5, height: 5)
                            Text("\(activeCount) live")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(GQColors.success)
                        }
                    }
                }
                VStack(spacing: 10) {
                    ForEach(clubs, id: \.id) { club in
                        popularClubCard(club)
                    }
                }
            }
        }
    }

    /// Richer variant of the rich card — larger avatar with a live dot
    /// ring, meta row with distance + member count, optional friends-in
    /// sub-line, and a pill Join button on the right.
    @ViewBuilder
    private func popularClubCard(_ club: Club) -> some View {
        let live = liveCount(for: club)
        let initial = String(club.name.prefix(1)).uppercased()
        let distance = distanceString(for: club)
        let friends = friendsInClub(club)

        Button { selectedClub = club } label: {
            HStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(GQGradients.primary)
                        .frame(width: 54, height: 54)
                        .overlay(
                            Text(initial)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        )
                    if live > 0 {
                        Circle()
                            .fill(GQColors.success)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(GQColors.surfaceBase, lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(club.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)
                            .lineLimit(1)
                        if club.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(GQGradients.primary)
                        }
                    }

                    HStack(spacing: 6) {
                        if live > 0 {
                            Text("\(live) lifting now")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(GQColors.success)
                            Text("·")
                                .font(.system(size: 11))
                                .foregroundColor(GQColors.textTertiary)
                        }
                        if let d = distance {
                            Text(d)
                                .font(.system(size: 11))
                                .foregroundColor(GQColors.textSecondary)
                            Text("·")
                                .font(.system(size: 11))
                                .foregroundColor(GQColors.textTertiary)
                        }
                        Text("\(club.memberCount) members")
                            .font(.system(size: 11))
                            .foregroundColor(GQColors.textTertiary)
                    }
                    .lineLimit(1)

                    if friends > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 9))
                                .foregroundColor(GQColors.textTertiary)
                            Text(friendsInFooter(club: club))
                                .font(.system(size: 10))
                                .foregroundColor(GQColors.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 8)

                Text("Join")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(GQGradients.primary))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .homeSocialCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Discover: lens + results

    /// Recommended pool, sorted/filtered by the active lens. Hero card
    /// takes the first item; the rich list shows the rest.
    /// R5.4: clubs with ≥2 friends + clubs that were explicitly shared
    /// to the user get a boost to the front of every lens (after the
    /// lens's own primary sort) so word-of-mouth always wins.
    private var lensedRecommendedClubs: [Club] {
        let pool = searchFilteredRecommended
        let primary: [Club]
        switch discoverLens {
        case .closest:
            primary = pool.sorted { a, b in
                let da: Double = {
                    guard let la = a.latitude, let lo = a.longitude else { return .infinity }
                    return distanceKm(lat: la, lon: lo)
                }()
                let db: Double = {
                    guard let la = b.latitude, let lo = b.longitude else { return .infinity }
                    return distanceKm(lat: la, lon: lo)
                }()
                return da < db
            }
        case .upcoming:
            primary = pool.sorted {
                let da = nextEvent(for: $0)?.date ?? .distantFuture
                let db = nextEvent(for: $1)?.date ?? .distantFuture
                return da < db
            }
        case .busiest:
            primary = pool.sorted { liveCount(for: $0) > liveCount(for: $1) }
        case .friends:
            primary = pool
                .filter { friendsInClub($0) > 0 }
                .sorted { friendsInClub($0) > friendsInClub($1) }
        case .fresh:
            primary = pool.sorted { $0.createdAt > $1.createdAt }
        }
        // Word-of-mouth boost. Stable across re-sorts because we
        // partition then concatenate rather than re-sorting by score.
        let shared = primary.filter { SharedClubStore.shared.sharer(for: $0.id) != nil }
        let manyFriends = primary.filter { friendsInClub($0) >= 2 && SharedClubStore.shared.sharer(for: $0.id) == nil }
        let rest = primary.filter { !shared.contains($0) && !manyFriends.contains($0) }
        return shared + manyFriends + rest
    }

    /// Tiny caps header above the lens bar: counts clubs matching the
    /// current lens and (when relevant) how many have events this week.
    @ViewBuilder
    private var discoverResultSummary: some View {
        let count = lensedRecommendedClubs.count
        let withEvents = lensedRecommendedClubs.filter { nextEvent(for: $0) != nil }.count
        let parts: [String] = {
            var p = [count == 1 ? "1 CLUB" : "\(count) CLUBS"]
            p.append(discoverLens.label.uppercased())
            if withEvents > 0 && discoverLens != .upcoming {
                p.append(withEvents == 1 ? "1 HAS AN EVENT" : "\(withEvents) HAVE EVENTS")
            }
            return p
        }()
        Text(parts.joined(separator: "  ·  "))
            .font(.system(size: 10, weight: .bold))
            .tracking(1.1)
            .foregroundColor(GQColors.textTertiary)
            .lineLimit(1)
    }

    // MARK: - Discover: lens bar

    @ViewBuilder
    private var discoverLensBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DiscoverLens.allCases) { lens in
                        discoverLensChip(lens)
                    }
                }
            }
            .scrollClipDisabled()
            mapLensButton
        }
    }

    /// Map quick-launch button anchored to the right edge of the lens
    /// bar. Replaces the old standalone map tile row — now the map is
    /// always reachable but never takes vertical space on its own.
    @ViewBuilder
    private var mapLensButton: some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            presentingMap = true
        } label: {
            Image(systemName: "map.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GQGradients.primary)
                .frame(width: 36, height: 34)
                .background(
                    Capsule().fill(GQColors.adaptiveOverlay(0.05))
                )
                .overlay(
                    Capsule().stroke(GQColors.borderDefault, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open map")
    }

    @ViewBuilder
    private func discoverLensChip(_ lens: DiscoverLens) -> some View {
        let selected = discoverLens == lens
        Button {
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                discoverLens = lens
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: lens.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolEffect(.bounce, value: selected)
                Text(lens.label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(selected ? .white : GQColors.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(
                    selected
                        ? AnyShapeStyle(GQGradients.primary)
                        : AnyShapeStyle(GQColors.adaptiveOverlay(0.05))
                )
            )
            .overlay(
                Capsule().stroke(
                    selected ? Color.clear : GQColors.borderDefault,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Discover: hero "For you" card

    @ViewBuilder
    private func discoverHeroCard(club: Club) -> some View {
        let reason = lensReason(for: club)
        let friendCount = friendsInClub(club)
        let initial = String(club.name.prefix(1)).uppercased()

        Button {
            selectedClub = club
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Text(reason)
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.0)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.28)))
                    Spacer()
                    Text("FOR YOU")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundColor(.white.opacity(0.65))
                }

                HStack(spacing: 12) {
                    ZStack {
                        MoodRing(mood: ClubSoundtrackLibrary.mood(for: club), inner: 54)
                        Circle()
                            .fill(.white.opacity(0.18))
                            .frame(width: 54, height: 54)
                        Text(initial)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(club.name)
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if club.isVerified {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white.opacity(0.9))
                            }
                        }
                        Text("\(club.memberCount) members  ·  \(ClubSoundtrackLibrary.mood(for: club).label.uppercased())  ·  \(club.resolvedCategory.rawValue)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                if !club.clubDescription.isEmpty {
                    Text(club.clubDescription)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if friendCount > 0 {
                    HStack(spacing: 8) {
                        avatarStack(count: min(friendCount, 4))
                        Text(friendsInFooter(club: club))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Join")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(GQColors.deepBlue)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.white))

                    Text("Explore")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))

                    Spacer()
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(heroBackdrop(club: club))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: GQColors.vividPurple.opacity(0.22), radius: 18, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    /// Layered backdrop for the hero card. If the top pick has a recent
    /// post with photoData, the photo sits behind a dark-purple gradient
    /// overlay so the text stays readable. No photo → pure gradient.
    @ViewBuilder
    private func heroBackdrop(club: Club) -> some View {
        ZStack {
            #if canImport(UIKit)
            if let data = mostRecentPost(for: club)?.photoData,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                LinearGradient(
                    colors: [
                        GQColors.vividPurple.opacity(0.78),
                        GQColors.deepBlue.opacity(0.85),
                        Color.black.opacity(0.7)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        GQColors.vividPurple.opacity(0.92),
                        GQColors.deepBlue.opacity(0.95),
                        Color.black.opacity(0.55)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            #else
            LinearGradient(
                colors: [
                    GQColors.vividPurple.opacity(0.92),
                    GQColors.deepBlue.opacity(0.95),
                    Color.black.opacity(0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            #endif
        }
    }

    /// "12 KM AWAY" / "EVENT TOMORROW" / "3 FRIENDS IN" / "NEW" — the
    /// eyebrow tag on the hero, tailored to why this pick surfaced.
    /// R5.1: when a friend is in the club, lead with their name so the
    /// recommendation reads as word-of-mouth ("OLIVIA'S CLUB · 0.4 KM").
    /// R5.5: if a friend explicitly shared this club, that takes priority.
    private func lensReason(for club: Club) -> String {
        if let sharer = SharedClubStore.shared.sharer(for: club.id) {
            return "\(sharer.uppercased()) SHARED THIS"
        }

        // Friend-led prefix when there's a known follower in the club.
        let friendPrefix: String? = {
            guard friendsInClub(club) > 0,
                  let firstName = firstFriendNameInClub(club)
            else { return nil }
            return "\(firstName.uppercased())'S CLUB"
        }()

        // Per-lens secondary detail (the lens-specific signal).
        let secondary: String = {
            switch discoverLens {
            case .closest:
                if let d = distanceString(for: club) { return d.uppercased() }
                return "NEAR YOU"
            case .upcoming:
                if let ev = nextEvent(for: club) {
                    return "EVENT \(relativeDayLabel(ev.date).uppercased())"
                }
                return "UPCOMING"
            case .busiest:
                let live = liveCount(for: club)
                return live > 0 ? "\(live) LIFTING NOW" : "ACTIVE"
            case .friends:
                let f = friendsInClub(club)
                return f == 1 ? "1 FRIEND IN" : "\(f) FRIENDS IN"
            case .fresh:
                return "NEW"
            }
        }()

        if let prefix = friendPrefix {
            return "\(prefix)  ·  \(secondary)"
        }
        return secondary
    }

    private func friendsInFooter(club: Club) -> String {
        let f = friendsInClub(club)
        if f == 0 { return "" }
        if let name = firstFriendNameInClub(club) {
            if f == 1 { return "\(name) is in" }
            return "\(name) + \(f - 1) friends are in"
        }
        return "\(f) friends in"
    }

    // MARK: - Discover: map tile

    @ViewBuilder
    private var discoverMapTile: some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            presentingMap = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [
                                    GQColors.cyanSpark.opacity(0.28),
                                    GQColors.deepBlue.opacity(0.22)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 68, height: 68)
                    // Stylized "pins" — faux minimap, no real MapKit render
                    // cost on this feed surface. Real map lives in the sheet.
                    ForEach(0..<3, id: \.self) { i in
                        let pts: [(CGFloat, CGFloat)] = [(-12, -10), (8, 3), (-4, 14)]
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(GQGradients.primary)
                            .offset(x: pts[i].0, y: pts[i].1)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(GQGradients.primary)
                        Text("Explore map")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)
                    }
                    Text("\(clubsWithCoordinates.count) clubs nearby")
                        .font(.system(size: 12))
                        .foregroundColor(GQColors.textTertiary)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .homeSocialCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Discover: by-vibe collections

    private struct DiscoverVibe: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let gradient: LinearGradient
        let matches: (ClubFeedView) -> [Club]
    }

    /// Themed club collections. Titles map to intent the category filter
    /// can't express: community strength, time-of-day, novelty, local
    /// nightlife. Tap → sets the lens closest to that intent (cheap
    /// approximation) with a selection pulse.
    private var discoverVibes: [DiscoverVibe] {
        [
            DiscoverVibe(
                id: "strong",
                title: "Strong community",
                subtitle: "High retention",
                icon: "heart.fill",
                gradient: LinearGradient(
                    colors: [GQColors.coralRed, GQColors.vividPurple],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                matches: { $0.searchFilteredRecommended.filter { $0.memberCount >= 20 } }
            ),
            DiscoverVibe(
                id: "morning",
                title: "Morning crews",
                subtitle: "Early risers",
                icon: "sunrise.fill",
                gradient: LinearGradient(
                    colors: [GQColors.sunsetOrange, GQColors.electricGold],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                matches: { view in
                    view.searchFilteredRecommended.filter { club in
                        view.allEvents.contains { ev in
                            ev.clubId == club.id
                                && Calendar.current.component(.hour, from: ev.date) < 10
                        }
                    }
                }
            ),
            DiscoverVibe(
                id: "new",
                title: "New gains",
                subtitle: "Just launched",
                icon: "sparkles",
                gradient: LinearGradient(
                    colors: [GQColors.cyanSpark, GQColors.deepBlue],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                matches: { view in
                    let cutoff = Date().addingTimeInterval(-60 * 24 * 3600)
                    return view.searchFilteredRecommended.filter { $0.createdAt > cutoff }
                }
            ),
            DiscoverVibe(
                id: "nearby_tonight",
                title: "Nearby tonight",
                subtitle: "Events within 25 km",
                icon: "moon.stars.fill",
                gradient: LinearGradient(
                    colors: [GQColors.vividPurple, GQColors.deepBlue],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                matches: { view in
                    view.searchFilteredRecommended.filter { club in
                        guard let la = club.latitude, let lo = club.longitude else { return false }
                        let d = view.distanceKm(lat: la, lon: lo)
                        guard d < 25 else { return false }
                        return view.allEvents.contains { ev in
                            ev.clubId == club.id && Calendar.current.isDateInToday(ev.date)
                        }
                    }
                }
            )
        ]
    }

    @ViewBuilder
    private var discoverVibeCollections: some View {
        let vibes = discoverVibes
        VStack(alignment: .leading, spacing: 10) {
            Text("BY VIBE")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.1)
                .foregroundColor(GQColors.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(vibes) { vibe in
                        vibeCollectionTile(vibe)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    @ViewBuilder
    private func vibeCollectionTile(_ vibe: DiscoverVibe) -> some View {
        let matches = vibe.matches(self)
        Button {
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            // Quick approximation — nudge the lens closest to this
            // vibe's intent. Bigger refactor would route to a filtered
            // sheet; this gets the feedback loop right for now.
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                switch vibe.id {
                case "strong":         discoverLens = .busiest
                case "morning":        discoverLens = .upcoming
                case "new":            discoverLens = .fresh
                case "nearby_tonight": discoverLens = .closest
                default:               break
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.22))
                        .frame(width: 38, height: 38)
                    Image(systemName: vibe.icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vibe.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(matches.isEmpty
                         ? vibe.subtitle
                         : "\(matches.count) club\(matches.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(width: 155, height: 130, alignment: .topLeading)
            .background(vibe.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Discover: snapshots row (photo-based discovery)

    /// Square photo tiles from recent posts in non-joined clubs. The
    /// "what does it actually look like?" surface — visual proof beats
    /// any amount of text descriptions for new clubs.
    @ViewBuilder
    private var snapshotsRow: some View {
        let posts = recentPostsForDiscovery
        if !posts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 5) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 11))
                            .foregroundStyle(GQGradients.primary)
                        Text("SNAPSHOTS")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.1)
                            .foregroundColor(GQColors.textTertiary)
                    }
                    Spacer()
                    Text("from clubs you don't follow")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(GQColors.textTertiary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(posts, id: \.id) { post in
                            snapshotTile(post: post)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    /// Up to 8 most-recent ClubPosts whose club is NOT joined by the user.
    /// Posts with photoData are preferred; falls back to recent posts
    /// without a photo so the row populates even before users upload.
    private var recentPostsForDiscovery: [ClubPost] {
        let myClubIds = Set(yourClubs.map(\.id))
        let nonJoined = allClubPosts.filter { !myClubIds.contains($0.clubId) }
        let withPhoto = nonJoined.filter { $0.photoData != nil }.sorted { $0.timestamp > $1.timestamp }
        if !withPhoto.isEmpty { return Array(withPhoto.prefix(8)) }
        return Array(nonJoined.sorted { $0.timestamp > $1.timestamp }.prefix(8))
    }

    /// One snapshot tile: 140×140, photo or category-glyph fallback,
    /// dark gradient overlay at the bottom for caption legibility, club
    /// name in caps. Tap → ClubDetailView.
    @ViewBuilder
    private func snapshotTile(post: ClubPost) -> some View {
        let club = allClubs.first(where: { $0.id == post.clubId })
        let size: CGFloat = 140
        Button {
            if let club { selectedClub = club }
        } label: {
            ZStack(alignment: .bottomLeading) {
                postPhotoOrPlaceholder(post: post, club: club ?? placeholderClub, size: size)

                // Caption gradient + club name overlay
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.7)],
                    startPoint: .center, endPoint: .bottom
                )
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    if let club {
                        Text(club.name.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.8)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if let dist = distanceString(for: club) {
                            Text(dist)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                }
                .padding(8)
                .frame(width: size, alignment: .leading)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(GQColors.borderDefault, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    /// Stub `Club` instance for snapshots whose source club has been
    /// removed. Keeps the placeholder tile renderable.
    private var placeholderClub: Club {
        Club(name: "Club", category: .generalFitness)
    }

    // MARK: - Discover: rich card list (lens-aware header)

    /// Trailing card list. Header rewrites to "POPULAR NEAR YOU" when
    /// the active lens is `.busiest` (the section formerly known as
    /// Popular merges into here so we don't show the same content
    /// twice). Otherwise reads "MORE TO EXPLORE."
    @ViewBuilder
    private var discoverRichCardList: some View {
        let rows = Array(lensedRecommendedClubs.dropFirst().prefix(10))
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 5) {
                        Image(systemName: discoverLens == .busiest ? "flame.fill" : "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(GQGradients.primary)
                        Text(discoverLens == .busiest ? "POPULAR NEAR YOU" : "MORE TO EXPLORE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.1)
                            .foregroundColor(GQColors.textTertiary)
                    }
                    Spacer()
                    let liveCardCount = rows.filter { liveCount(for: $0) > 0 }.count
                    if liveCardCount > 0 {
                        HStack(spacing: 4) {
                            Circle().fill(GQColors.success).frame(width: 5, height: 5)
                            Text("\(liveCardCount) live")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(GQColors.success)
                        }
                    }
                }
                VStack(spacing: 10) {
                    ForEach(rows, id: \.id) { club in
                        richClubCard(club)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func richClubCard(_ club: Club) -> some View {
        let live = liveCount(for: club)
        let initial = String(club.name.prefix(1)).uppercased()
        let hasPost = mostRecentPost(for: club) != nil
        let mood = ClubSoundtrackLibrary.mood(for: club)
        Button {
            selectedClub = club
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    MoodRing(mood: mood, inner: 46)
                    Circle()
                        .fill(GQGradients.primary)
                        .frame(width: 46, height: 46)
                    Text(initial)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
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
                        if live > 0 {
                            HStack(spacing: 3) {
                                Circle().fill(GQColors.success).frame(width: 5, height: 5)
                                Text("\(live) live")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(GQColors.success)
                            }
                        }
                    }
                    Text(richSubtitle(club))
                        .font(.system(size: 12))
                        .foregroundColor(GQColors.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if hasPost {
                    clubPostThumbnail(club, size: 44)
                }

                Text("Join")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(GQGradients.primary))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .homeSocialCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    /// Rich-card subtitle: time-of-next-event · distance · friends ·
    /// category — order locked so the row scans the same on every card.
    /// Trimmed to three segments to stay one line.
    private func richSubtitle(_ club: Club) -> String {
        var parts: [String] = []
        if let ev = nextEvent(for: club) {
            parts.append(relativeDayLabel(ev.date))
        }
        if let d = distanceString(for: club) { parts.append(d) }
        let friends = friendsInClub(club)
        if friends > 0 {
            parts.append(friends == 1 ? "1 friend" : "\(friends) friends")
        }
        parts.append(club.resolvedCategory.rawValue)
        return parts.prefix(3).joined(separator: "  ·  ")
    }

    // MARK: - Discover: media helpers

    /// Most-recent ClubPost for a club, by timestamp. Drives photo
    /// thumbnails on the rich card and the hero backdrop.
    private func mostRecentPost(for club: Club) -> ClubPost? {
        allClubPosts
            .filter { $0.clubId == club.id }
            .max { $0.timestamp < $1.timestamp }
    }

    /// Square thumbnail of a club's most-recent post photo. Falls back
    /// to a gradient tile with the club's category glyph when there's
    /// no photo data, so the row keeps a stable visual rhythm.
    @ViewBuilder
    private func clubPostThumbnail(_ club: Club, size: CGFloat) -> some View {
        ZStack {
            postPhotoOrPlaceholder(post: mostRecentPost(for: club), club: club, size: size)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(GQColors.borderDefault, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func postPhotoOrPlaceholder(post: ClubPost?, club: Club, size: CGFloat) -> some View {
        #if canImport(UIKit)
        if let data = post?.photoData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            postPlaceholderTile(club: club, size: size)
        }
        #else
        postPlaceholderTile(club: club, size: size)
        #endif
    }

    @ViewBuilder
    private func postPlaceholderTile(club: Club, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            GQColors.deepBlue.opacity(0.55),
                            GQColors.vividPurple.opacity(0.55)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
            Image(systemName: club.resolvedCategory.icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
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
        }
        .scrollClipDisabled()
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
        .padding(.vertical, 10)
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
            .padding(.vertical, 10)
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
    @Query private var allFriends: [Friend]

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

    // R4 — drop-in reactions persisted in-memory keyed by session id.
    // Real impl would persist to a "ClubReaction" model + sync.
    @State private var reactionCounts: [String: [String: Int]] = [:]
    // R4.6 — clubs where user opted in to "notify me when friends train here".
    @State private var notifyOptedIn: Set<UUID> = ClubNotifyStore.load()
    // R6 — quick-create flow. One sheet that branches into 4 modes.
    @State private var showingQuickCreate = false
    @State private var showingCameraCapture = false
    @State private var showingVoiceNote = false
    // R6.5 — anonymous browsing access (3 days). Loaded onAppear.
    @State private var anonStartedAt: Date?

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
        ScrollView {
            VStack(spacing: 10) {
                coverBanner             // R7+ — wide cover photo
                aliveAmbientStripForClub
                    .padding(.horizontal, 16)
                clubStoriesRail         // R7+ — 24h ephemeral bubbles
                detailHeader
                anonymousBrowsingPill   // R6.5 — guest access on non-joined clubs
                postEventPromptBanner   // R6.4 — "Drop a clip" 60min after event ends
                activeInThisClubStrip
                liveStreamsSection      // R4.5 — full live cards with reactions
                notifyToggleRow         // R4.6 — opt in to friend-training notifs
                joinButton
                quickCreateBar          // R6 — camera/voice/event/post quick actions
                featuredWallSection     // R7+ — 3×3 admin-curated photo wall
                clubPlaylistSection     // R7.8 — shared soundtrack
                yourStorySection        // R5.6 — your-club history strip
                streakAnniversaryRibbon // R5.7 — recurring-event streak callout
                weeklyHighlightCard     // R5.8 — Sunday auto-stitched reel
                onThisDayCard           // R5.10 — replay from a year ago
                prReplayCard            // R7.10 — slow-mo PR card
                clubSectionPicker
                sectionContent
                Spacer(minLength: 40)
            }
            .padding(.top, 0)
        }
        .onAppear {
            anonStartedAt = AnonymousBrowsingStore.shared.startedAt(for: club.id)
        }
        .gqPageBackground()
        .navigationTitle(club.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(GQColors.background, for: .navigationBar)
        .instagramBack()
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
        .sheet(isPresented: $showingQuickCreate) {
            QuickCreateMenuSheet(
                onCamera: {
                    showingQuickCreate = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { showingCameraCapture = true }
                },
                onVoice: {
                    showingQuickCreate = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { showingVoiceNote = true }
                },
                onEvent: {
                    showingQuickCreate = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { showingCreateEvent = true }
                },
                onPost: {
                    showingQuickCreate = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { showingNewPost = true }
                }
            )
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingCameraCapture) {
            CameraQuickCaptureSheet(club: club, profile: profile)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingVoiceNote) {
            VoiceNotePostSheet(club: club, profile: profile)
                .presentationDetents([.height(420)])
        }
        .alert("Error", isPresented: $showClubServiceError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(clubServiceError ?? "An unexpected error occurred.")
        }
    }

    // MARK: - Header

    /// Profile-style club header — big avatar on the left, three stat
    /// columns on the right (Members / Events / Live Now), then name,
    /// category pill, description, and location chip. Mirrors the
    /// ProfileView header language so Club detail reads as a peer
    /// "identity" page rather than a utility screen.
    @ViewBuilder
    private var detailHeader: some View {
        let live = liveMembersInThisClub.count
        let upcoming = allEvents.filter { $0.clubId == club.id && $0.date > Date() }.count
        let cat = club.resolvedCategory

        VStack(alignment: .leading, spacing: 12) {
            // Row 1 — avatar + stat columns
            HStack(spacing: 16) {
                Group {
                    #if canImport(UIKit)
                    if let imageData = club.imageData, let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(GQColors.borderSubtle, lineWidth: 0.5))
                    } else {
                        ClubMonogramAvatar(club: club, size: 72)
                    }
                    #else
                    ClubMonogramAvatar(club: club, size: 72)
                    #endif
                }

                HStack(spacing: 0) {
                    clubStatColumn(value: "\(club.memberCount)", label: club.memberCount == 1 ? "Member" : "Members")
                    clubStatColumn(value: "\(upcoming)", label: upcoming == 1 ? "Event" : "Events")
                    clubStatColumn(
                        value: "\(live)",
                        label: "Live now",
                        valueColor: live > 0 ? GQColors.success : GQColors.textPrimary
                    )
                }
            }

            // Row 2 — name + verification/lock
            HStack(spacing: 6) {
                Text(club.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(2)
                if club.isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(GQGradients.primary)
                }
                if !club.isOpen {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(GQColors.textTertiary)
                }
                Spacer(minLength: 0)
            }

            // Row 3 — category pill + location chip
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: cat.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(cat.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(GQGradients.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(GQColors.deepBlue.opacity(0.10))
                .clipShape(Capsule())

                if let location = club.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 10, weight: .semibold))
                        Text(location)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundColor(GQColors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(GQColors.adaptiveOverlay(0.05))
                    .clipShape(Capsule())
                }
            }

            // Row 4 — description
            if !club.clubDescription.isEmpty {
                Text(club.clubDescription)
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textSecondary)
                    .lineLimit(3)
            }
        }
        .padding(16)
        .homeSocialCard(cornerRadius: 16)
        .padding(.horizontal, 16)
    }

    /// Stat column used in the detail header — value on top, small
    /// tracked-caps label below. Mirrors `igStatColumn` on ProfileView.
    @ViewBuilder
    private func clubStatColumn(value: String, label: String, valueColor: Color = GQColors.textPrimary) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(valueColor)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundColor(GQColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
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
                    .fill(GQGradients.primary)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Text(String(m.name.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                    )
                    .presenceRing(m.userId, size: 38)
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
        .reactionTarget(to: m.userId, name: m.name, from: profile.id)
    }

    // MARK: - R4: Live stream cards + drop-in reactions

    /// Full-bleed cards for members currently mid-session in this club.
    /// Each card has a drop-in reaction row (🔥 💪 👀) — tap fires
    /// haptic + count-up. The plan calls these "live workout streams";
    /// they're the engagement surface that turns the club from a
    /// directory into a place.
    @ViewBuilder
    private var liveStreamsSection: some View {
        let live = liveMembersInThisClub
        if !live.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GQGradients.primary)
                    Text("LIVE STREAMS")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundColor(GQColors.textTertiary)
                    Spacer()
                    Text("Drop a reaction · they'll see it")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(GQColors.textTertiary)
                }
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(live, id: \.userId) { member in
                            liveStreamCard(member)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollClipDisabled()
            }
        }
    }

    @ViewBuilder
    private func liveStreamCard(_ m: (userId: UUID, name: String, workoutType: String?)) -> some View {
        let sessionId = "\(club.id.uuidString)-\(m.userId.uuidString)"
        let firstName = m.name.split(separator: " ").first.map(String.init) ?? m.name
        let initial = String(firstName.first ?? "?").uppercased()
        let presenceMin = presenceStates.first { $0.userId == m.userId }?.minutesIn ?? 0
        let workout = m.workoutType?.capitalized ?? "Training"
        let counts = reactionCounts[sessionId] ?? [:]

        VStack(alignment: .leading, spacing: 0) {
            // Faux video stage: gradient + animated equalizer + initial
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [
                        mapPinColor(for: club.resolvedCategory),
                        GQColors.vividPurple.opacity(0.85),
                        Color.black.opacity(0.7)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Centered initial — stand-in until real video stream
                Text(initial)
                    .font(.system(size: 70, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Top: LIVE pill + minutes
                HStack(spacing: 6) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(GQColors.coralRed)
                            .frame(width: 6, height: 6)
                            .modifier(LivePulseModifier())
                        Text("LIVE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.2)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    Spacer()
                    Text("\(presenceMin)m")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                }
                .padding(10)

                // Bottom-left: equalizer + name + now-playing track
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    HStack(spacing: 6) {
                        equalizerIndicator
                        Text(firstName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Text(workout)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)

                    let track = ClubSoundtrackLibrary.nowPlaying(for: m.userId)
                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(track.title) · \(track.artist)")
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.black.opacity(0.35)))
                }
                .padding(12)
            }
            .frame(width: 220, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            // Reaction row underneath the card
            HStack(spacing: 8) {
                dropInReactionButton(sessionId: sessionId, emoji: "🔥", count: counts["fire"] ?? 0, key: "fire")
                dropInReactionButton(sessionId: sessionId, emoji: "💪", count: counts["flex"] ?? 0, key: "flex")
                dropInReactionButton(sessionId: sessionId, emoji: "👀", count: counts["watch"] ?? 0, key: "watch")
                Spacer()
            }
            .padding(.top, 8)
        }
        .reactionTarget(to: m.userId, name: m.name, from: profile.id)
    }

    @ViewBuilder
    private func dropInReactionButton(sessionId: String, emoji: String, count: Int, key: String) -> some View {
        Button {
            bumpReaction(sessionId: sessionId, key: key)
        } label: {
            reactionPillLabel(emoji: emoji, count: count)
        }
        .buttonStyle(.plain)
    }

    /// Pulls the dict mutation out of the Button closure — keeps the
    /// type-checker happy on a long-ish view body.
    private func bumpReaction(sessionId: String, key: String) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        var dict = reactionCounts[sessionId] ?? [:]
        let current = dict[key] ?? 0
        dict[key] = current + 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
            reactionCounts[sessionId] = dict
        }
    }

    @ViewBuilder
    private func reactionPillLabel(emoji: String, count: Int) -> some View {
        let active = count > 0
        let fill: AnyShapeStyle = active
            ? AnyShapeStyle(GQGradients.primary.opacity(0.12))
            : AnyShapeStyle(GQColors.adaptiveOverlay(0.05))
        let strokeColor: Color = active ? GQColors.deepBlue.opacity(0.3) : GQColors.borderDefault
        HStack(spacing: 4) {
            Text(emoji)
                .font(.system(size: 14))
            if active {
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(GQColors.textPrimary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, active ? 10 : 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(fill))
        .overlay(Capsule().stroke(strokeColor, lineWidth: 1))
    }

    /// Tiny 3-bar equalizer animation. Stand-in for "audio is playing
    /// during this session" — primes Release 7's music integration.
    @ViewBuilder
    private var equalizerIndicator: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = sin(t * 4 + Double(i) * 0.7) * 0.5 + 0.5
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 2.5, height: 4 + CGFloat(phase) * 8)
                }
            }
        }
        .frame(width: 12, height: 12)
    }

    /// Tiny ring around the LIVE pill dot — pulses every 1.2s.
    private struct LivePulseModifier: ViewModifier {
        @State private var on = false
        func body(content: Content) -> some View {
            content
                .scaleEffect(on ? 1.15 : 0.9)
                .opacity(on ? 1.0 : 0.7)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        on = true
                    }
                }
        }
    }

    // MARK: - R4.6: Notify-me opt-in

    @ViewBuilder
    private var notifyToggleRow: some View {
        let opted = notifyOptedIn.contains(club.id)
        Button {
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            if opted {
                notifyOptedIn.remove(club.id)
            } else {
                notifyOptedIn.insert(club.id)
            }
            ClubNotifyStore.save(notifyOptedIn)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: opted ? "bell.fill" : "bell")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(opted ? GQColors.electricGold : GQColors.textSecondary)
                Text(opted
                     ? "Notifying you when friends train here"
                     : "Notify me when friends train here")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(opted ? GQColors.textPrimary : GQColors.textSecondary)
                Spacer()
                if opted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(GQColors.electricGold)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(opted ? GQColors.electricGold.opacity(0.10) : GQColors.adaptiveOverlay(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(opted ? GQColors.electricGold.opacity(0.35) : GQColors.borderDefault, lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - R5: Friendship surface + shared memory (inside club detail)

    /// R5.6 — Per-club "Your story" section. Auto-curated from posts +
    /// member milestones. Only renders when the user is a member; for
    /// non-members the surface would be aspirational, not earned.
    @ViewBuilder
    private var yourStorySection: some View {
        if isMember {
            let stats = yourStoryStats
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 5) {
                    Image(systemName: "book.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(GQGradients.primary)
                    Text("YOUR STORY HERE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundColor(GQColors.textTertiary)
                    Spacer()
                }

                Text(stats.headline)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(2)

                Text(stats.sub)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(GQColors.textTertiary)

                if !stats.photoStrip.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(stats.photoStrip, id: \.id) { post in
                                yourStoryPhotoTile(post: post)
                            }
                        }
                    }
                    .scrollClipDisabled()
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(GQGradients.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(GQGradients.primary.opacity(0.18), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }

    private struct YourStoryStats {
        let headline: String
        let sub: String
        let photoStrip: [ClubPost]
    }

    /// Tally of the user's footprint in this club + a co-member shoutout.
    /// Posts authored by the user act as a session proxy for demo data.
    private var yourStoryStats: YourStoryStats {
        let myPosts = clubPosts.filter { $0.clubId == club.id && $0.authorId == profile.id }
        let mySessions = myPosts.count
        let memberDate = club.createdAt
        let monthsIn = max(1, Calendar.current.dateComponents([.month], from: memberDate, to: Date()).month ?? 1)
        let topMate = topCoMemberName

        let headline: String = {
            if mySessions == 0 {
                return "You joined \(club.name)"
            }
            if let mate = topMate {
                return "\(mySessions) session\(mySessions == 1 ? "" : "s") · \(min(mySessions, 12)) with \(mate)"
            }
            return "\(mySessions) session\(mySessions == 1 ? "" : "s") logged"
        }()

        let sub: String = {
            let dateStr = memberDate.formatted(.dateTime.month(.wide).year())
            return "Member since \(dateStr) · \(monthsIn) month\(monthsIn == 1 ? "" : "s")"
        }()

        let photoStrip = clubPosts
            .filter { $0.clubId == club.id && $0.photoData != nil }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(6)

        return YourStoryStats(headline: headline, sub: sub, photoStrip: Array(photoStrip))
    }

    /// First friend (in the SocialSeeder fake-friend pool) who's also
    /// a member of this club. Surfaced in the headline as "12 with X".
    private var topCoMemberName: String? {
        let friendIds = Set(SocialSeeder.fakeUsers.prefix(6).map(\.id))
        let coMember = club.memberIds.first { friendIds.contains($0) }
        guard let id = coMember,
              let name = SocialSeeder.fakeUsers.first(where: { $0.id == id })?.name
        else { return nil }
        return name.split(separator: " ").first.map(String.init)
    }

    @ViewBuilder
    private func yourStoryPhotoTile(post: ClubPost) -> some View {
        let size: CGFloat = 64
        Group {
            #if canImport(UIKit)
            if let data = post.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                placeholderTile(size: size)
            }
            #else
            placeholderTile(size: size)
            #endif
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(GQColors.borderDefault, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func placeholderTile(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [GQColors.deepBlue.opacity(0.5), GQColors.vividPurple.opacity(0.5)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: club.resolvedCategory.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            )
    }

    /// R5.7 — Streak / anniversary ribbon. Pulled from the club's
    /// recurring events + a synthetic week count derived from how long
    /// the recurring event has been on the calendar.
    @ViewBuilder
    private var streakAnniversaryRibbon: some View {
        if let pick = streakPick {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(GQColors.electricGold.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(GQColors.electricGold)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("STREAK")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.0)
                        .foregroundColor(GQColors.electricGold)
                    Text("\(pick.title) · Week \(pick.weeks) in a row")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(GQColors.electricGold.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(GQColors.electricGold.opacity(0.35), lineWidth: 1)
            )
            .padding(.horizontal, 16)
        }
    }

    private struct StreakPick { let title: String; let weeks: Int }

    private var streakPick: StreakPick? {
        let recurring = allEvents.filter { $0.clubId == club.id && $0.isRecurring }
        guard let ev = recurring.first else { return nil }
        // Synthetic week count: weeks since the club was created, capped
        // at 26. Real impl would count completed instances.
        let weeks = min(
            26,
            max(1, Calendar.current.dateComponents([.weekOfYear], from: club.createdAt, to: Date()).weekOfYear ?? 1)
        )
        return StreakPick(title: ev.title, weeks: weeks)
    }

    /// R5.8 — Weekly highlight reel card. Cycles through recent club
    /// posts every 1.2s. Only surfaces on Sundays (or when there's a
    /// fresh enough cluster of posts to warrant a recap).
    @ViewBuilder
    private var weeklyHighlightCard: some View {
        let highlights = weeklyHighlightPosts
        if !highlights.isEmpty && shouldShowWeeklyReel {
            Button {
                // Tap → simply opens the first post (full club timeline
                // already shows the rest). Real impl would launch a reel.
                showingNewPost = false
            } label: {
                ZStack(alignment: .bottomLeading) {
                    weeklyHighlightCarousel(posts: highlights)
                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.7)],
                        startPoint: .center, endPoint: .bottom
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WEEKLY HIGHLIGHTS")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.1)
                            .foregroundColor(.white.opacity(0.85))
                        Text("\(club.name) · this week")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Text("\(highlights.count) moment\(highlights.count == 1 ? "" : "s") from your club")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(14)
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
        }
    }

    private var weeklyHighlightPosts: [ClubPost] {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        return clubPosts
            .filter { $0.clubId == club.id && $0.timestamp >= cutoff }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Show on Sundays OR whenever there are 3+ recent posts in the
    /// last week — gives the demo a chance to render any day of the
    /// week as long as the club is active.
    private var shouldShowWeeklyReel: Bool {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return weekday == 1 || weeklyHighlightPosts.count >= 3
    }

    @ViewBuilder
    private func weeklyHighlightCarousel(posts: [ClubPost]) -> some View {
        TimelineView(.periodic(from: Date(), by: 1.2)) { context in
            let idx = posts.isEmpty ? 0
                : Int(context.date.timeIntervalSinceReferenceDate / 1.2) % posts.count
            let post = posts.indices.contains(idx) ? posts[idx] : posts.first
            if let post {
                postBackdrop(post: post)
                    .id(post.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: posts.map(\.id))
    }

    @ViewBuilder
    private func postBackdrop(post: ClubPost) -> some View {
        #if canImport(UIKit)
        if let data = post.photoData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LinearGradient(
                colors: [
                    mapPinColor(for: club.resolvedCategory),
                    GQColors.vividPurple.opacity(0.85),
                    Color.black
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        #else
        LinearGradient(
            colors: [GQColors.deepBlue, GQColors.vividPurple, .black],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        #endif
    }

    /// R5.10 — "On this day" replay. Surfaces a post from a year ago,
    /// with ±7 day tolerance. Demo-friendly even when seeds don't have
    /// year-old data: falls back to the oldest post in the club so the
    /// surface doesn't disappear in cold-start installs.
    @ViewBuilder
    private var onThisDayCard: some View {
        if let pick = onThisDayPick {
            Button {
                // Real impl: open the original post in detail.
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(GQColors.vividPurple.opacity(0.18))
                            .frame(width: 50, height: 50)
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(GQColors.vividPurple)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("ON THIS DAY · \(pick.daysAgo / 365) YR AGO")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(GQColors.vividPurple)
                        Text(pick.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(GQColors.textTertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(GQColors.adaptiveOverlay(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(GQColors.borderDefault, lineWidth: 0.5)
                )
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
        }
    }

    private struct OnThisDayPick {
        let title: String
        let daysAgo: Int
    }

    private var onThisDayPick: OnThisDayPick? {
        let posts = clubPosts.filter { $0.clubId == club.id }
        guard !posts.isEmpty else { return nil }
        let now = Date()
        // Real "year ago" match within ±7 days
        if let yearAgo = posts.first(where: { post in
            let days = Int(now.timeIntervalSince(post.timestamp) / 86400)
            return abs(days - 365) <= 7
        }) {
            let days = Int(now.timeIntervalSince(yearAgo.timestamp) / 86400)
            return OnThisDayPick(title: postTitle(yearAgo), daysAgo: days)
        }
        // Fallback: oldest post older than 90 days, framed as "a while back"
        if let oldest = posts.sorted(by: { $0.timestamp < $1.timestamp }).first {
            let days = Int(now.timeIntervalSince(oldest.timestamp) / 86400)
            if days >= 90 {
                return OnThisDayPick(title: postTitle(oldest), daysAgo: max(days, 365))
            }
        }
        return nil
    }

    private func postTitle(_ post: ClubPost) -> String {
        if !post.content.isEmpty {
            return post.content.prefix(80).description
        }
        return "\(post.authorName.split(separator: " ").first ?? "A member") shared a moment"
    }

    // MARK: - R6: Create + low-friction surfaces

    /// Quick-create bar — 4 large icon-led buttons giving low-friction
    /// access to camera, voice, event, and write-a-post creation. Sits
    /// above the timeline as the "you're a creator here" affordance.
    @ViewBuilder
    private var quickCreateBar: some View {
        if isMember || isAnonActive {
            HStack(spacing: 8) {
                quickCreateButton(icon: "camera.fill",       label: "Camera") {
                    showingCameraCapture = true
                }
                quickCreateButton(icon: "waveform",          label: "Voice") {
                    showingVoiceNote = true
                }
                quickCreateButton(icon: "calendar.badge.plus", label: "Event") {
                    showingCreateEvent = true
                }
                quickCreateButton(icon: "square.and.pencil", label: "Post") {
                    showingNewPost = true
                }
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func quickCreateButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(GQGradients.primary.opacity(0.10))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(GQGradients.primary)
                }
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(GQColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// R6.4 — Post-event prompt. Surfaces when a club event ended
    /// within the last 60 minutes. Tap → camera quick-capture flow.
    @ViewBuilder
    private var postEventPromptBanner: some View {
        if let pick = recentlyEndedEvent {
            Button {
                showingCameraCapture = true
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(GQColors.electricGold.opacity(0.18))
                            .frame(width: 36, height: 36)
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(GQColors.electricGold)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("HOW WAS IT?")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.0)
                            .foregroundColor(GQColors.electricGold)
                        Text("Drop a clip from \(pick.title)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Capture")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(GQGradients.primary))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(GQColors.electricGold.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(GQColors.electricGold.opacity(0.35), lineWidth: 1)
                )
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
        }
    }

    /// Most recent club event whose end time is within the last 60 min.
    /// `endDate` may be nil — we approximate using `date + 1h` in that
    /// case which is a safe default for most workout-style events.
    private var recentlyEndedEvent: ClubEvent? {
        let now = Date()
        let cutoff = now.addingTimeInterval(-60 * 60)
        return allEvents
            .filter { $0.clubId == club.id }
            .compactMap { ev -> (ClubEvent, Date)? in
                let end = ev.endDate ?? ev.date.addingTimeInterval(3600)
                guard end <= now && end >= cutoff else { return nil }
                return (ev, end)
            }
            .sorted { $0.1 > $1.1 }
            .first
            .map { $0.0 }
    }

    // MARK: - R6.5: Anonymous browsing

    /// True when user is in an active 3-day guest window for this club.
    private var isAnonActive: Bool {
        guard let started = anonStartedAt else { return false }
        return Date().timeIntervalSince(started) < (3 * 24 * 3600)
    }

    /// "Try for 3 days" entry pill on non-joined clubs, plus a guest
    /// indicator while the trial is active.
    @ViewBuilder
    private var anonymousBrowsingPill: some View {
        if !isMember {
            if isAnonActive {
                HStack(spacing: 8) {
                    Image(systemName: "eye.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(GQColors.vividPurple)
                    Text("BROWSING AS GUEST")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.0)
                        .foregroundColor(GQColors.vividPurple)
                    Spacer()
                    if let started = anonStartedAt {
                        Text(anonRemainingLabel(started: started))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(GQColors.textTertiary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(GQColors.vividPurple.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(GQColors.vividPurple.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 16)
            } else {
                Button {
                    AnonymousBrowsingStore.shared.start(for: club.id)
                    anonStartedAt = AnonymousBrowsingStore.shared.startedAt(for: club.id)
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(GQColors.deepBlue)
                        Text("Try for 3 days · no commitment")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)
                        Spacer()
                        Text("Start")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(GQGradients.primary))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(GQColors.adaptiveOverlay(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(GQColors.borderDefault, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func anonRemainingLabel(started: Date) -> String {
        let total: TimeInterval = 3 * 24 * 3600
        let remaining = max(0, total - Date().timeIntervalSince(started))
        let hours = Int(remaining / 3600)
        let days = hours / 24
        if days >= 1 {
            return "\(days) day\(days == 1 ? "" : "s") left"
        } else {
            return "\(max(1, hours)) h left"
        }
    }

    // MARK: - R7+: Cover banner

    /// Edge-to-edge 16:9 cover image at the very top of the detail
    /// page. Clubs without `imageData` fall back to a category-tinted
    /// gradient so the layout never collapses.
    @ViewBuilder
    /// Alive ambient strip pinned at the top of club detail. Shows live
    /// counts scoped to followed friends + this specific club's members.
    private var aliveAmbientStripForClub: some View {
        let now = Date()
        let followedIds = Set(allFriends.filter { $0.userId == profile.id }.map(\.odId))
        let clubmateIds = Set(club.memberIds).subtracting([profile.id])
        let liveFriendIds = presenceStates
            .filter { followedIds.contains($0.userId) && Self.isLiveForAlive($0, now: now) }
            .map(\.userId)
        let liveClubmateIds = presenceStates
            .filter { clubmateIds.contains($0.userId) && Self.isLiveForAlive($0, now: now) }
            .map(\.userId)
        return AmbientHeaderStrip(
            friendCount: liveFriendIds.count,
            clubmateCount: liveClubmateIds.count,
            avatarPeek: Array((liveFriendIds + liveClubmateIds).prefix(3))
        )
    }

    private static func isLiveForAlive(_ s: UserPresenceState, now: Date) -> Bool {
        switch s.status {
        case .arriving, .training, .resting: break
        default: return false
        }
        if let started = s.startedAt, now.timeIntervalSince(started) > 3 * 3600 { return false }
        return true
    }

    private var coverBanner: some View {
        ZStack(alignment: .bottomLeading) {
            #if canImport(UIKit)
            if let data = club.imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
            } else {
                coverFallback
            }
            #else
            coverFallback
            #endif

            // Subtle bottom-fade for legibility behind anything that
            // overlaps the bottom edge.
            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.45)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 200)

            HStack(spacing: 5) {
                Image(systemName: club.resolvedCategory.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(club.resolvedCategory.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.32)))
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .frame(height: 200)
    }

    @ViewBuilder
    private var coverFallback: some View {
        LinearGradient(
            colors: [
                mapPinColor(for: club.resolvedCategory),
                GQColors.vividPurple.opacity(0.85),
                Color.black.opacity(0.5)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }

    // MARK: - R7+: Stories rail

    /// 24h ephemeral story bubbles atop club detail. One bubble per
    /// distinct author who posted in the last 24 hours.
    @ViewBuilder
    private var clubStoriesRail: some View {
        let stories = recentStories
        if !stories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(stories, id: \.author.id) { story in
                        storyBubble(story)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .scrollClipDisabled()
        }
    }

    private struct StoryBubble {
        let author: (id: UUID, name: String, username: String)
        let post: ClubPost
    }

    private var recentStories: [StoryBubble] {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        let recent = clubPosts
            .filter { $0.clubId == club.id && $0.timestamp >= cutoff && $0.photoData != nil }
            .sorted { $0.timestamp > $1.timestamp }

        var seen = Set<UUID>()
        var out: [StoryBubble] = []
        for post in recent {
            if seen.insert(post.authorId).inserted,
               let user = SocialSeeder.fakeUsers.first(where: { $0.id == post.authorId }) {
                out.append(StoryBubble(author: user, post: post))
            }
        }
        return Array(out.prefix(8))
    }

    @ViewBuilder
    private func storyBubble(_ story: StoryBubble) -> some View {
        let firstName = story.author.name.split(separator: " ").first.map(String.init) ?? story.author.name
        VStack(spacing: 5) {
            ZStack {
                // Gradient ring — Instagram story aesthetic
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [GQColors.coralRed, GQColors.electricGold, GQColors.vividPurple, GQColors.coralRed],
                            center: .center
                        ),
                        lineWidth: 2.5
                    )
                    .frame(width: 64, height: 64)

                Group {
                    #if canImport(UIKit)
                    if let data = story.post.photoData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(GQGradients.primary)
                            .frame(width: 56, height: 56)
                            .overlay(
                                Text(String(firstName.first ?? "?").uppercased())
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            )
                    }
                    #else
                    Circle()
                        .fill(GQGradients.primary)
                        .frame(width: 56, height: 56)
                    #endif
                }
            }
            Text(firstName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(GQColors.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 70)
        .presenceRing(story.author.id, size: 64)
        .reactionTarget(to: story.author.id, name: story.author.name, from: profile.id)
    }

    // MARK: - R7+: Featured 3×3 photo wall

    /// Top-9 photos in this club by like count. Sits below the join
    /// button as a visual lookbook for both members and visitors.
    @ViewBuilder
    private var featuredWallSection: some View {
        let posts = featuredWallPosts
        if posts.count >= 6 {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "rectangle.grid.3x2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GQGradients.primary)
                    Text("FEATURED")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundColor(GQColors.textTertiary)
                    Spacer()
                    Text("Top moments from members")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(GQColors.textTertiary)
                }
                .padding(.horizontal, 16)

                let cols = [GridItem(.flexible(), spacing: 4),
                            GridItem(.flexible(), spacing: 4),
                            GridItem(.flexible(), spacing: 4)]
                LazyVGrid(columns: cols, spacing: 4) {
                    ForEach(Array(posts.prefix(9)), id: \.id) { post in
                        featuredTile(post: post)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var featuredWallPosts: [ClubPost] {
        clubPosts
            .filter { $0.clubId == club.id && $0.photoData != nil }
            .sorted { $0.likeCount > $1.likeCount }
    }

    @ViewBuilder
    private func featuredTile(post: ClubPost) -> some View {
        let isVideo = post.content.hasPrefix("🎥")
        ZStack(alignment: .topTrailing) {
            #if canImport(UIKit)
            if let data = post.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fill)
                    .clipped()
            } else {
                Color.gray.opacity(0.2)
                    .aspectRatio(1, contentMode: .fill)
            }
            #else
            Color.gray.opacity(0.2).aspectRatio(1, contentMode: .fill)
            #endif

            if isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(5)
                    .background(Circle().fill(Color.black.opacity(0.5)))
                    .padding(6)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - R7.8: Club soundtrack playlist

    /// Shared playlist section. Lists the club's 4–5 track soundtrack
    /// with a mood ring around the playlist icon. Add-track CTA is
    /// cosmetic — collaborative playlists ship with R7's full server
    /// integration later.
    @ViewBuilder
    private var clubPlaylistSection: some View {
        let tracks = ClubSoundtrackLibrary.soundtrack(for: club)
        let mood = ClubSoundtrackLibrary.mood(for: club)
        if !tracks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(GQGradients.primary)
                    Text("THE SOUNDTRACK")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundColor(GQColors.textTertiary)
                    Spacer()
                    Button {
                        // Cosmetic — opens the post sheet for now
                        showingNewPost = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("Add track")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(GQColors.deepBlue)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)

                VStack(spacing: 6) {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { idx, track in
                        playlistRow(index: idx, track: track, mood: mood)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func playlistRow(index: Int, track: Track, mood: TrackMood) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(mood.color.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: index == 0 ? "play.fill" : "music.note")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(mood.color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                Text("\(track.artist)  ·  \(track.bpm) BPM  ·  \(track.mood.label)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            if index == 0 {
                Text("WALK-IN")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(mood.color))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(GQColors.adaptiveOverlay(0.04))
        )
    }

    // MARK: - R7.10: PR replay slowdown card

    /// Shows when a recent (last 7 days) club post by a friend reads
    /// like a PR signal — keyword sniff for "PR", "max", "deadlift",
    /// etc. Stylized as a slow-mo card with a play indicator.
    @ViewBuilder
    private var prReplayCard: some View {
        if let post = recentPRPost {
            let firstName = post.authorName.split(separator: " ").first.map(String.init) ?? post.authorName
            Button {
                // Real impl: opens replay player.
            } label: {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [
                            GQColors.electricGold.opacity(0.85),
                            GQColors.coralRed.opacity(0.85),
                            Color.black.opacity(0.6)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    // Speed indicator stripes
                    HStack(spacing: 4) {
                        ForEach(0..<5, id: \.self) { i in
                            Capsule()
                                .fill(Color.white.opacity(0.18 - Double(i) * 0.03))
                                .frame(width: 24 + CGFloat(i) * 8, height: 3)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(20)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: "play.slash.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("PR REPLAY · SLOW-MO · 0.5×")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.0)
                        }
                        .foregroundColor(.white.opacity(0.85))
                        Text("\(firstName)'s lift")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                            Text("Crowd noise on · tap to replay")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                        }
                    }
                    .padding(14)
                }
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
        }
    }

    private var recentPRPost: ClubPost? {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let keywords = ["pr", "max", "deadlift", "1rm", "set", "squat", "bench"]
        return clubPosts
            .filter { $0.clubId == club.id && $0.timestamp >= cutoff }
            .first { post in
                let lower = post.content.lowercased()
                return keywords.contains { lower.contains($0) }
            }
    }

    /// R5.9 — Personal context annotation surfaced under a friend's
    /// post. The app pretends to remember context that's hard to track
    /// otherwise: PR proximity, comeback sessions, frequency milestones.
    /// Demo: hashes the post id into a small bank of canned annotations
    /// so it's deterministic but feels personal. Real impl would look
    /// up workout history + profile tags.
    func personalContextLine(for post: ClubPost) -> String? {
        let bank: [String] = [
            "First squat session in 6 weeks",
            "10 lbs from her bench PR",
            "Back to lifting after a 6-month break",
            "Match streak: 5th week in a row",
            "First Wednesday session this month",
            "Came back from a calf strain"
        ]
        // Skip your own posts — context would be redundant.
        guard post.authorId != profile.id else { return nil }
        // Stable mapping per post id, but only ~40% of posts get a line
        // so the surface doesn't read as noise.
        let hash = abs(post.id.hashValue)
        guard hash % 5 < 2 else { return nil }
        return bank[hash % bank.count]
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
            HStack(spacing: 8) {
                Button { showingNewPost = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Post")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(GQGradients.primary)
                    .clipShape(Capsule())
                }

                Button {
                    selectedSection = .members
                    showPartnerOnly = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Find Partner")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(GQColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(GQColors.adaptiveOverlay(0.06))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(GQColors.borderDefault.opacity(0.5), lineWidth: 0.5)
                    )
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

// MARK: - Grouped card container (edge-to-edge white section)

/// Full-width white section band — edge-to-edge (no horizontal inset)
/// so it matches the Friends + Discover feeds. A subtle borderProminent
/// hairline at top and bottom visually separates it from the gray page
/// gaps between sections. Internal 16pt vertical padding gives rows
/// breathing room; row-level horizontal padding supplies their own
/// content indent.
private struct GroupedCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .background(GQColors.surfaceBase)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(GQColors.borderProminent)
                    .frame(height: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(GQColors.borderProminent)
                    .frame(height: 0.5)
            }
            // Light drop shadow — matches the Friends feed depth
            // treatment so bands read as layered surfaces on top of
            // the gray page instead of flat color blocks.
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

extension View {
    /// Wraps a section in a full-width edge-to-edge white band —
    /// matches the Friends / Discover feed surface language.
    func groupedCard() -> some View {
        modifier(GroupedCardModifier())
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

// MARK: - Release 2: Map as a Place

/// Time-window the map filter scrubber can be set to. "Active" pins
/// are clubs that have an event in the window; pins outside fade out.
enum MapTimeWindow: String, CaseIterable, Identifiable {
    case now, tonight, tomorrowAM, weekend, nextWeek
    var id: String { rawValue }
    var label: String {
        switch self {
        case .now:        return "Now"
        case .tonight:    return "Tonight"
        case .tomorrowAM: return "Tomorrow AM"
        case .weekend:    return "Weekend"
        case .nextWeek:   return "Next Week"
        }
    }

    /// Window range for matching events. `now` is special — it returns
    /// no range; pin "active"-ness in this mode comes from `liveCount`.
    func dateRange(from base: Date = Date()) -> ClosedRange<Date>? {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: base)
        switch self {
        case .now:
            return nil
        case .tonight:
            // 5pm → midnight today
            let start = cal.date(byAdding: .hour, value: 17, to: startOfDay) ?? base
            let end = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? base
            return start...end
        case .tomorrowAM:
            let tomorrow = cal.date(byAdding: .day, value: 1, to: startOfDay) ?? base
            let start = cal.date(byAdding: .hour, value: 5, to: tomorrow) ?? tomorrow
            let end = cal.date(byAdding: .hour, value: 12, to: tomorrow) ?? tomorrow
            return start...end
        case .weekend:
            // Next upcoming Saturday 6am → Sunday 11pm
            let weekday = cal.component(.weekday, from: base) // 1 Sun..7 Sat
            let daysUntilSat = (7 - weekday + 7) % 7  // 0 if today is Sat
            let satStart = cal.date(byAdding: .day, value: daysUntilSat, to: startOfDay) ?? base
            let start = cal.date(byAdding: .hour, value: 6, to: satStart) ?? satStart
            let end = cal.date(byAdding: .hour, value: 23, to: cal.date(byAdding: .day, value: 1, to: satStart) ?? satStart) ?? satStart
            return start...end
        case .nextWeek:
            let start = cal.date(byAdding: .day, value: 7, to: startOfDay) ?? base
            let end = cal.date(byAdding: .day, value: 14, to: startOfDay) ?? base
            return start...end
        }
    }
}

/// Brand-pin color per club category. Coarse buckets so the map reads
/// as 4–5 distinct colors rather than 16 muddy ones.
private func mapPinColor(for category: ClubCategory) -> Color {
    switch category {
    case .running, .cycling, .swimming:
        return GQColors.cyanSpark      // endurance / cardio = cyan
    case .weightlifting, .crossfit, .hiit:
        return GQColors.vividPurple    // strength = purple
    case .basketball, .soccer, .tennis, .volleyball, .hockey:
        return GQColors.sunsetOrange   // ball/team sports = orange
    case .yoga, .dance, .climbing:
        return GQColors.coralRed       // flow / movement = pink
    case .martialArts:
        return GQColors.electricGold   // combat = gold
    case .generalFitness:
        return GQColors.deepBlue       // catch-all = brand blue
    }
}

/// Discrete heights the bottom sheet snaps to.
private enum BottomSheetHeight {
    case collapsed, half, full
    func points(in size: CGSize) -> CGFloat {
        switch self {
        case .collapsed: return 110
        case .half:      return size.height * 0.45
        case .full:      return size.height * 0.85
        }
    }
}

/// Full-screen Map mode for Clubs. Time scrubber on top, MapKit map
/// with category-colored pulse pins, draggable bottom sheet listing
/// visible clubs, and a slide-up mini hero on pin tap. Designed to
/// answer "what's happening when, where" at a glance.
struct ClubsMapMode: View {
    let clubs: [Club]
    let events: [ClubEvent]
    let profile: UserProfile
    let userClubIds: Set<UUID>
    let liveCount: (Club) -> Int
    let nextEventFor: (Club) -> ClubEvent?
    let friendsInClub: (Club) -> Int
    let firstFriendName: (Club) -> String?
    let distanceString: (Club) -> String?
    let recentPost: (Club) -> ClubPost?
    let onSelectClub: (Club) -> Void

    @State private var timeWindow: MapTimeWindow = .now
    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 44.225, longitude: -76.490),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))
    @State private var sheetHeight: BottomSheetHeight = .half
    @State private var dragOffset: CGFloat = 0
    @State private var pinSelection: Club? = nil
    @State private var anchorCoord: CLLocationCoordinate2D? = nil
    @State private var anchorRadiusKm: Double = 5.0

    private var mappableClubs: [Club] {
        clubs.filter { $0.latitude != nil && $0.longitude != nil }
    }

    /// Clubs filtered by the time window. `.now` keeps everything;
    /// other windows keep only clubs with a matching event.
    private var clubsInWindow: [Club] {
        guard let range = timeWindow.dateRange() else { return mappableClubs }
        return mappableClubs.filter { club in
            events.contains { ev in ev.clubId == club.id && range.contains(ev.date) }
        }
    }

    /// Clubs further filtered by the long-press anchor radius (when set).
    private var visibleClubs: [Club] {
        guard let anchor = anchorCoord else { return clubsInWindow }
        return clubsInWindow.filter {
            guard let lat = $0.latitude, let lon = $0.longitude else { return false }
            return haversineKm(lat1: anchor.latitude, lon1: anchor.longitude, lat2: lat, lon2: lon) <= anchorRadiusKm
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                mapLayer
                    .ignoresSafeArea(edges: .bottom)

                heatLayer
                    .allowsHitTesting(false)
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    timeScrubber
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                    Spacer()
                }

                if let club = pinSelection {
                    miniHeroCard(club)
                        .padding(.horizontal, 12)
                        .padding(.bottom, currentSheetHeight(in: geo.size) + 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                bottomSheet(in: geo.size)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: pinSelection?.id)
            .animation(.easeInOut(duration: 0.18), value: timeWindow)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: sheetHeight)
        }
    }

    // MARK: - Map layer

    @ViewBuilder
    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                ForEach(mappableClubs) { club in
                    Annotation(club.name, coordinate: clubCoord(club)) {
                        clubPinView(club)
                    }
                }
                if let anchor = anchorCoord {
                    Annotation("Search here", coordinate: anchor) {
                        anchorPin
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .onTapGesture { _ in
                withAnimation { pinSelection = nil }
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.45)
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onEnded { value in
                        switch value {
                        case .second(true, let drag):
                            if let location = drag?.location,
                               let coord = proxy.convert(location, from: .local) {
                                #if canImport(UIKit)
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                #endif
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    anchorCoord = coord
                                    sheetHeight = .half
                                }
                            }
                        default:
                            break
                        }
                    }
            )
        }
    }

    /// Coords with deterministic jitter for clubs missing real lat/lon
    /// — pulled from the Kingston center so demo data still spreads.
    private func clubCoord(_ club: Club) -> CLLocationCoordinate2D {
        if let lat = club.latitude, let lon = club.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        let seed = abs(club.id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        let jLat = Double((seed % 60) - 30) / 3500.0
        let jLon = Double(((seed / 60) % 60) - 30) / 3500.0
        return CLLocationCoordinate2D(latitude: 44.225 + jLat, longitude: -76.490 + jLon)
    }

    // MARK: - Pin view

    @ViewBuilder
    private func clubPinView(_ club: Club) -> some View {
        let live = liveCount(club)
        let isInWindow = isClubInWindow(club)
        let isFriendsClub = friendsInClub(club) > 0
        let baseColor = mapPinColor(for: club.resolvedCategory)
        let initial = String(club.name.prefix(1)).uppercased()

        Button {
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            withAnimation { pinSelection = (pinSelection?.id == club.id) ? nil : club }
            if let lat = club.latitude, let lon = club.longitude {
                withAnimation(.easeInOut(duration: 0.4)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        span: MKCoordinateSpan(latitudeDelta: 0.025, longitudeDelta: 0.025)
                    ))
                }
            }
        } label: {
            ZStack {
                if live > 0 && isInWindow {
                    pulseRing(baseColor: baseColor, intensity: live)
                }

                ZStack {
                    Circle()
                        .fill(baseColor)
                        .frame(width: 38, height: 38)
                    Text(initial)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    if isFriendsClub {
                        Circle()
                            .fill(GQGradients.primary)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .offset(x: 14, y: -14)
                    }
                }
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
                .opacity(isInWindow ? 1 : 0.35)
                .scaleEffect(pinSelection?.id == club.id ? 1.15 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    /// Repeating outward pulse — radius scales with `intensity` (live
    /// count). 1.6s cycle, alpha fades from 0.35 → 0.
    @ViewBuilder
    private func pulseRing(baseColor: Color, intensity: Int) -> some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let cycle = 1.6
            let phase = (elapsed.truncatingRemainder(dividingBy: cycle)) / cycle
            let baseRadius: CGFloat = 22
            let burst = CGFloat(min(intensity, 5)) * 6
            let scale = 1 + CGFloat(phase) * (0.6 + burst / 30)
            let alpha = (1 - phase) * 0.35

            Circle()
                .fill(baseColor)
                .frame(width: baseRadius * 2, height: baseRadius * 2)
                .scaleEffect(scale)
                .opacity(alpha)
        }
        .frame(width: 44, height: 44)
    }

    @ViewBuilder
    private var anchorPin: some View {
        ZStack {
            Circle()
                .fill(GQColors.electricGold)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(.white, lineWidth: 2.5))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            Image(systemName: "scope")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
    }

    // MARK: - Heat overlay

    /// Soft heat overlay derived from club coordinate clusters. Uses
    /// SwiftUI radial gradients positioned via a coordinate→screen
    /// projection. Intentionally low-fi: a real heatmap would need a
    /// custom MTKView — this is decorative texture, not analysis.
    @ViewBuilder
    private var heatLayer: some View {
        MapReader { proxy in
            GeometryReader { geo in
                ForEach(visibleClubs) { club in
                    if let pt = proxy.convert(clubCoord(club), to: .local) {
                        let live = liveCount(club)
                        let radius: CGFloat = 60 + CGFloat(min(live, 5)) * 14
                        let color = mapPinColor(for: club.resolvedCategory)
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [color.opacity(live > 0 ? 0.18 : 0.08), .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: radius
                                )
                            )
                            .frame(width: radius * 2, height: radius * 2)
                            .position(pt)
                    }
                }
            }
        }
    }

    // MARK: - Time scrubber

    @ViewBuilder
    private var timeScrubber: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MapTimeWindow.allCases) { window in
                    timeWindowChip(window)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        )
    }

    @ViewBuilder
    private func timeWindowChip(_ window: MapTimeWindow) -> some View {
        let selected = timeWindow == window
        Button {
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            timeWindow = window
            pinSelection = nil
        } label: {
            Text(window.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(selected ? .white : GQColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(
                        selected
                            ? AnyShapeStyle(GQGradients.primary)
                            : AnyShapeStyle(Color.clear)
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mini hero card

    @ViewBuilder
    private func miniHeroCard(_ club: Club) -> some View {
        let next = nextEventFor(club)
        let live = liveCount(club)
        let initial = String(club.name.prefix(1)).uppercased()

        Button {
            onSelectClub(club)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    if let data = recentPost(club)?.photoData {
                        #if canImport(UIKit)
                        if let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        #endif
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(mapPinColor(for: club.resolvedCategory))
                            .frame(width: 64, height: 64)
                            .overlay(
                                Text(initial)
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(club.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(GQColors.textPrimary)
                            .lineLimit(1)
                        if live > 0 {
                            HStack(spacing: 3) {
                                Circle().fill(GQColors.success).frame(width: 5, height: 5)
                                Text("\(live) live")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(GQColors.success)
                            }
                        }
                    }
                    Text(miniSubtitle(club: club, next: next))
                        .font(.system(size: 11))
                        .foregroundColor(GQColors.textTertiary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text("Open")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(GQGradients.primary))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(GQColors.surfaceBase)
                    .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(GQColors.borderDefault, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func miniSubtitle(club: Club, next: ClubEvent?) -> String {
        var parts: [String] = []
        if let next {
            let day = relativeDayString(next.date)
            let time = next.date.formatted(date: .omitted, time: .shortened)
            parts.append("\(day) \(time)")
        }
        if let d = distanceString(club) { parts.append(d) }
        let f = friendsInClub(club)
        if f > 0, let name = firstFriendName(club) {
            parts.append(f == 1 ? "\(name) is in" : "\(name) + \(f - 1) friends")
        }
        return parts.isEmpty
            ? club.resolvedCategory.rawValue
            : parts.prefix(3).joined(separator: "  ·  ")
    }

    // MARK: - Bottom sheet

    @ViewBuilder
    private func bottomSheet(in size: CGSize) -> some View {
        let height = max(60, currentSheetHeight(in: size) - dragOffset)
        VStack(spacing: 0) {
            Capsule()
                .fill(GQColors.textTertiary.opacity(0.4))
                .frame(width: 40, height: 4)
                .padding(.top, 8)

            sheetHeader
                .padding(.horizontal, 16)
                .padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(visibleClubs, id: \.id) { club in
                        sheetClubRow(club)
                    }
                    if visibleClubs.isEmpty {
                        Text(timeWindow == .now ? "No clubs in view" : "Nothing scheduled · try a different window")
                            .font(.system(size: 12))
                            .foregroundColor(GQColors.textTertiary)
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .frame(width: size.width, height: height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(GQColors.surfaceBase)
                .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    let velocity = value.predictedEndTranslation.height
                    dragOffset = 0
                    sheetHeight = nextSheetHeight(from: sheetHeight, velocity: velocity)
                    #if canImport(UIKit)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                }
        )
    }

    private func currentSheetHeight(in size: CGSize) -> CGFloat {
        sheetHeight.points(in: size)
    }

    private func nextSheetHeight(from current: BottomSheetHeight, velocity: CGFloat) -> BottomSheetHeight {
        let pull = velocity < -200
        let push = velocity > 200
        switch (current, pull, push) {
        case (.collapsed, true, _): return .half
        case (.half, true, _):      return .full
        case (.full, _, true):      return .half
        case (.half, _, true):      return .collapsed
        default:
            if velocity < -50 { return current == .collapsed ? .half : (current == .half ? .full : .full) }
            if velocity > 50  { return current == .full ? .half : (current == .half ? .collapsed : .collapsed) }
            return current
        }
    }

    @ViewBuilder
    private var sheetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if anchorCoord != nil {
                    Text("WITHIN \(Int(anchorRadiusKm)) KM")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.0)
                        .foregroundColor(GQColors.electricGold)
                }
                Text(sheetTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Text(sheetSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
            }
            Spacer()
            if anchorCoord != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { anchorCoord = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(GQColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var sheetTitle: String {
        switch timeWindow {
        case .now:        return "All clubs"
        case .tonight:    return "Tonight"
        case .tomorrowAM: return "Tomorrow morning"
        case .weekend:    return "This weekend"
        case .nextWeek:   return "Next week"
        }
    }

    private var sheetSubtitle: String {
        let count = visibleClubs.count
        let activeCount = visibleClubs.filter { liveCount($0) > 0 }.count
        var parts: [String] = []
        parts.append("\(count) club\(count == 1 ? "" : "s")")
        if activeCount > 0 { parts.append("\(activeCount) live") }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder
    private func sheetClubRow(_ club: Club) -> some View {
        let live = liveCount(club)
        let next = nextEventFor(club)
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                pinSelection = club
            }
            if let lat = club.latitude, let lon = club.longitude {
                withAnimation(.easeInOut(duration: 0.4)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    ))
                }
            }
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(mapPinColor(for: club.resolvedCategory))
                    .frame(width: 38, height: 38)
                    .overlay(
                        Text(String(club.name.prefix(1)).uppercased())
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(club.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)
                            .lineLimit(1)
                        if live > 0 {
                            HStack(spacing: 3) {
                                Circle().fill(GQColors.success).frame(width: 4, height: 4)
                                Text("\(live)")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(GQColors.success)
                            }
                        }
                    }
                    Text(rowSubtitle(club: club, next: next))
                        .font(.system(size: 11))
                        .foregroundColor(GQColors.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let d = distanceString(club) {
                    Text(d)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(GQColors.textSecondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(pinSelection?.id == club.id ? GQColors.adaptiveOverlay(0.06) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowSubtitle(club: Club, next: ClubEvent?) -> String {
        var parts: [String] = []
        if let next {
            let day = relativeDayString(next.date)
            let time = next.date.formatted(date: .omitted, time: .shortened)
            parts.append("\(day) \(time)")
        }
        let f = friendsInClub(club)
        if f > 0 { parts.append(f == 1 ? "1 friend in" : "\(f) friends in") }
        parts.append(club.resolvedCategory.rawValue)
        return parts.prefix(2).joined(separator: "  ·  ")
    }

    // MARK: - Helpers

    private func isClubInWindow(_ club: Club) -> Bool {
        guard let range = timeWindow.dateRange() else {
            // .now → "active" if anyone's training there right now
            return liveCount(club) > 0 || true   // pin always renders; fade is handled elsewhere
        }
        return events.contains { $0.clubId == club.id && range.contains($0.date) }
    }

    private func relativeDayString(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)    { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    private func haversineKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return r * c
    }
}

// MARK: - Release 3: Watch (Reels-style media discovery)

/// One full-bleed clip in the Watch feed. Sourced from a club post
/// (preferred — has photo) or, when no post exists, synthesized from a
/// club's category gradient. Holds enough context to render the overlay
/// without re-querying.
struct WatchClip: Identifiable, Hashable {
    let id: String
    let club: Club
    let post: ClubPost?

    static func == (lhs: WatchClip, rhs: WatchClip) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Discovery filter on top of the Watch feed.
enum WatchFilter: String, CaseIterable, Identifiable {
    case forYou, nearMe, friendsClubs, trending, saved
    var id: String { rawValue }
    var label: String {
        switch self {
        case .forYou:       return "For You"
        case .nearMe:       return "Near Me"
        case .friendsClubs: return "Friends' clubs"
        case .trending:     return "Trending"
        case .saved:        return "Saved"
        }
    }
    var icon: String {
        switch self {
        case .forYou:       return "sparkles"
        case .nearMe:       return "location.fill"
        case .friendsClubs: return "person.2.fill"
        case .trending:     return "flame.fill"
        case .saved:        return "bookmark.fill"
        }
    }
}

/// Vertical-scroll, full-bleed Reels-style discovery feed for clubs.
/// Auto-cycling photo background acts as the "video" stand-in; ready to
/// be swapped for real `AVPlayer` clips when video data lands.
struct ClubsWatchMode: View {
    let allClubs: [Club]
    let userClubIds: Set<UUID>
    let posts: [ClubPost]
    let events: [ClubEvent]
    let profile: UserProfile
    let nextEventFor: (Club) -> ClubEvent?
    let friendsInClub: (Club) -> Int
    let distanceString: (Club) -> String?
    let onSelectClub: (Club) -> Void

    @State private var filter: WatchFilter = .forYou
    @State private var vibeTag: String? = nil       // active "this vibe" filter
    @State private var moodFilter: TrackMood? = nil // R7.5 — "Lift to this"
    @State private var savedClipIds: Set<String> = WatchSavedStore.load()

    /// Recommendable pool — clubs the user is NOT in.
    private var nonJoinedClubs: [Club] {
        allClubs.filter { !userClubIds.contains($0.id) }
    }

    /// Clip stream. One clip per recent post (with photo or without —
    /// without falls back to a category gradient). Then a tail of
    /// "synthetic" clips for clubs that have no posts yet so the feed
    /// stays populated for new installs.
    private var clips: [WatchClip] {
        let pool = nonJoinedClubs
        let poolIds = Set(pool.map(\.id))
        let postedClips: [WatchClip] = posts
            .filter { poolIds.contains($0.clubId) }
            .sorted { $0.timestamp > $1.timestamp }
            .compactMap { post in
                guard let club = pool.first(where: { $0.id == post.clubId }) else { return nil }
                return WatchClip(id: "post-\(post.id.uuidString)", club: club, post: post)
            }
        let postedClubIds = Set(postedClips.map(\.club.id))
        let bareClubs = pool.filter { !postedClubIds.contains($0.id) }
        let bareClips = bareClubs.map { club in
            WatchClip(id: "club-\(club.id.uuidString)", club: club, post: nil)
        }
        return postedClips + bareClips
    }

    /// Apply the active filter + optional vibe tag on top of the clip stream.
    private var visibleClips: [WatchClip] {
        var out = clips
        switch filter {
        case .forYou:
            // For You = original order (recency-first), no extra filter
            break
        case .nearMe:
            out = out.filter { distanceString($0.club) != nil }
                .sorted { lhs, rhs in
                    (distanceString(lhs.club) ?? "") < (distanceString(rhs.club) ?? "")
                }
        case .friendsClubs:
            out = out.filter { friendsInClub($0.club) > 0 }
        case .trending:
            out = out.sorted { lhs, rhs in
                postCount(for: lhs.club) > postCount(for: rhs.club)
            }
        case .saved:
            out = out.filter { savedClipIds.contains($0.id) }
        }
        if let vibe = vibeTag {
            out = out.filter { clip in
                clip.club.tags.contains(vibe)
                    || clip.club.resolvedCategory.rawValue.lowercased() == vibe.lowercased()
            }
        }
        if let mood = moodFilter {
            out = out.filter { ClubSoundtrackLibrary.mood(for: $0.club) == mood }
        }
        return out
    }

    private func postCount(for club: Club) -> Int {
        posts.filter { $0.clubId == club.id }.count
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        cinemaCard(geo: geo)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id("cinema")
                        ForEach(visibleClips) { clip in
                            clipCard(clip, in: geo.size)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .id(clip.id)
                        }
                        if visibleClips.isEmpty {
                            emptyState
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                }
                .scrollTargetBehaviorIfAvailable()
                .ignoresSafeArea(edges: .bottom)

                topControls
            }
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorSchemeIfPossible(.dark)
    }

    // MARK: - Top controls (filter chips + vibe banner)

    @ViewBuilder
    private var topControls: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WatchFilter.allCases) { f in
                        watchFilterChip(f)
                    }
                }
                .padding(.horizontal, 12)
            }
            .scrollClipDisabled()

            if let vibe = vibeTag {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 10, weight: .semibold))
                    Text("VIBE · \(vibe.uppercased())")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.0)
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { vibeTag = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.15)))
            }

            if let mood = moodFilter {
                HStack(spacing: 6) {
                    Image(systemName: "scope")
                        .font(.system(size: 10, weight: .semibold))
                    Text("LIFT TO · \(mood.label.uppercased())")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.0)
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { moodFilter = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(mood.color.opacity(0.5)))
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func watchFilterChip(_ f: WatchFilter) -> some View {
        let selected = filter == f
        Button {
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                filter = f
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: f.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(f.label)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(selected ? .black : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(selected ? Color.white : Color.white.opacity(0.18))
            )
            .overlay(
                Capsule().stroke(selected ? Color.clear : Color.white.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Clip card

    @ViewBuilder
    private func clipCard(_ clip: WatchClip, in size: CGSize) -> some View {
        let club = clip.club
        let next = nextEventFor(club)
        let dist = distanceString(club)
        let friends = friendsInClub(club)
        let isSaved = savedClipIds.contains(clip.id)

        ZStack(alignment: .bottom) {
            // Background — photo or category-gradient placeholder.
            clipBackground(clip, size: size)

            // Bottom darkening gradient for legibility
            LinearGradient(
                colors: [Color.clear, Color.clear, Color.black.opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            // Tap-to-detail catcher (full-bleed below the overlay)
            Button { onSelectClub(club) } label: {
                Color.clear
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            // Overlay: meta + actions
            VStack(alignment: .leading, spacing: 10) {
                Spacer()

                HStack(spacing: 5) {
                    Text(club.resolvedCategory.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.1)
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(club.name)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if club.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.95))
                    }
                }

                Text(clipMetaLine(next: next, dist: dist, friends: friends))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)

                // R7.4 — Track strip with waveform + Lift to this
                clipTrackStrip(club: club)

                HStack(spacing: 10) {
                    Button { onSelectClub(club) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("Join")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(GQColors.deepBlue)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.white))
                    }
                    .buttonStyle(.plain)

                    Button {
                        let firstTag = club.tags.first ?? club.resolvedCategory.rawValue.lowercased()
                        #if canImport(UIKit)
                        UISelectionFeedbackGenerator().selectionChanged()
                        #endif
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                            vibeTag = (vibeTag == firstTag) ? nil : firstTag
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 11, weight: .semibold))
                            Text("This vibe")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        toggleSave(clip)
                    } label: {
                        Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(isSaved ? GQColors.electricGold : .white)
                            .padding(8)
                            .background(Circle().fill(Color.black.opacity(0.3)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// R7.4 + R7.5 — Track strip below the meta line. Shows a track,
    /// an animated waveform, and a "Lift to this" button that filters
    /// the feed to clips of clubs with the same mood.
    @ViewBuilder
    private func clipTrackStrip(club: Club) -> some View {
        let track = ClubSoundtrackLibrary.soundtrack(for: club).first ?? ClubSoundtrackLibrary.bank[0]
        let mood = ClubSoundtrackLibrary.mood(for: club)
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                TrackEqualizerView(bars: 4, height: 12, color: .white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.black.opacity(0.32)))

            Text("\(track.title) · \(track.artist)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer(minLength: 6)

            Button {
                #if canImport(UIKit)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                    moodFilter = (moodFilter == mood) ? nil : mood
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "scope")
                        .font(.system(size: 10, weight: .bold))
                    Text("Lift to this")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func clipMetaLine(next: ClubEvent?, dist: String?, friends: Int) -> String {
        var parts: [String] = []
        if let next {
            let cal = Calendar.current
            let day: String = {
                if cal.isDateInToday(next.date) { return "Today" }
                if cal.isDateInTomorrow(next.date) { return "Tomorrow" }
                return next.date.formatted(.dateTime.weekday(.abbreviated))
            }()
            let time = next.date.formatted(date: .omitted, time: .shortened)
            parts.append("\(day) \(time)")
        }
        if let dist { parts.append(dist) }
        if friends > 0 {
            parts.append(friends == 1 ? "1 friend in" : "\(friends) friends in")
        }
        return parts.prefix(3).joined(separator: "  ·  ")
    }

    @ViewBuilder
    private func clipBackground(_ clip: WatchClip, size: CGSize) -> some View {
        ZStack {
            #if canImport(UIKit)
            if let data = clip.post?.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .modifier(KenBurnsModifier())
            } else {
                clipPlaceholder(clip: clip, size: size)
            }
            #else
            clipPlaceholder(clip: clip, size: size)
            #endif
        }
    }

    @ViewBuilder
    private func clipPlaceholder(clip: WatchClip, size: CGSize) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    mapPinColor(for: clip.club.resolvedCategory),
                    Color.black.opacity(0.7)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: clip.club.resolvedCategory.icon)
                .font(.system(size: 120, weight: .semibold))
                .foregroundColor(.white.opacity(0.2))
                .modifier(KenBurnsModifier())
        }
        .frame(width: size.width, height: size.height)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.slash.fill")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.5))
            Text("Nothing in this filter yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Text("Try a different lens or clear the active vibe.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(40)
    }

    private func toggleSave(_ clip: WatchClip) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        if savedClipIds.contains(clip.id) {
            savedClipIds.remove(clip.id)
        } else {
            savedClipIds.insert(clip.id)
        }
        WatchSavedStore.save(savedClipIds)
    }

    // MARK: - Cinema card

    /// Weekly tailored 60-second-feel reel: cycles through 6–8 strong
    /// matches every 1.5s on a single hero card. Pinned to the top of
    /// the Watch feed.
    @ViewBuilder
    private func cinemaCard(geo: GeometryProxy) -> some View {
        let cinemaPicks = Array(cinemaSelection.prefix(8))
        ZStack {
            cinemaCarousel(picks: cinemaPicks, size: geo.size)

            LinearGradient(
                colors: [Color.black.opacity(0.45), Color.clear, Color.black.opacity(0.85)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                Spacer()
                Text("CINEMA  ·  THIS WEEK")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.7))
                Text("Clubs you'd love")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text("\(cinemaPicks.count) clubs picked for you · swipe up to start")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                cinemaSoundtrackLabel(picks: cinemaPicks)
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Start")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.white))
                    Spacer()
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 80)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Track label that swaps in sync with the cinemaCarousel slide
    /// rotation (1.5s cycle). Animated waveform + ♪ Track · Artist.
    @ViewBuilder
    private func cinemaSoundtrackLabel(picks: [Club]) -> some View {
        TimelineView(.periodic(from: Date(), by: 1.5)) { context in
            let idx = picks.isEmpty ? 0
                : Int(context.date.timeIntervalSinceReferenceDate / 1.5) % picks.count
            let club = picks.indices.contains(idx) ? picks[idx] : nil
            if let club {
                let tracks = ClubSoundtrackLibrary.soundtrack(for: club)
                let track = tracks.first ?? ClubSoundtrackLibrary.bank[0]
                HStack(spacing: 8) {
                    TrackEqualizerView(bars: 4, height: 14, color: .white)
                    Text("♪ \(track.title) · \(track.artist)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.35)))
                .id(club.id)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: picks.count)
    }

    /// Tailored picks for Cinema. Heuristic: prefer clubs with photos +
    /// upcoming events + at least one friend in. Falls back to any
    /// non-joined club if the curated set is too thin.
    private var cinemaSelection: [Club] {
        let primary = nonJoinedClubs.filter {
            mostRecentPostFor($0) != nil
                && (nextEventFor($0) != nil || friendsInClub($0) > 0)
        }
        if primary.count >= 4 { return primary }
        return Array(primary + nonJoinedClubs.filter { !primary.contains($0) })
    }

    private func mostRecentPostFor(_ club: Club) -> ClubPost? {
        posts.filter { $0.clubId == club.id }.max { $0.timestamp < $1.timestamp }
    }

    @ViewBuilder
    private func cinemaCarousel(picks: [Club], size: CGSize) -> some View {
        TimelineView(.periodic(from: Date(), by: 1.5)) { context in
            let idx = picks.isEmpty ? 0
                : Int(context.date.timeIntervalSinceReferenceDate / 1.5) % picks.count
            let club = picks.indices.contains(idx) ? picks[idx] : nil
            if let club {
                cinemaSlide(club: club, size: size)
                    .transition(.opacity)
                    .id(club.id)
            } else {
                Color.black
            }
        }
        .animation(.easeInOut(duration: 0.5), value: picks.count)
    }

    @ViewBuilder
    private func cinemaSlide(club: Club, size: CGSize) -> some View {
        ZStack {
            #if canImport(UIKit)
            if let data = mostRecentPostFor(club)?.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .modifier(KenBurnsModifier())
            } else {
                LinearGradient(
                    colors: [
                        mapPinColor(for: club.resolvedCategory),
                        GQColors.vividPurple.opacity(0.8),
                        Color.black
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(width: size.width, height: size.height)
                Image(systemName: club.resolvedCategory.icon)
                    .font(.system(size: 140, weight: .semibold))
                    .foregroundColor(.white.opacity(0.2))
            }
            #else
            LinearGradient(
                colors: [
                    mapPinColor(for: club.resolvedCategory),
                    GQColors.vividPurple.opacity(0.8),
                    Color.black
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .frame(width: size.width, height: size.height)
            #endif
        }
    }
}

/// Subtle slow-zoom on a clip background. 6-second cycle, scales 1.00→1.08.
private struct KenBurnsModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                    scale = 1.08
                }
            }
    }
}

/// In-memory + UserDefaults-backed bookmark store for Watch clips. A
/// proper persistent tab on the profile is deferred — for now Saved
/// surfaces inside the Watch filter bar so users can find their list.
private enum WatchSavedStore {
    private static let key = "watchSavedClipIds.v1"
    static func load() -> Set<String> {
        let arr = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        return Set(arr)
    }
    static func save(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: key)
    }
}

/// Tracks which club ids the user has opted in to "notify me when friends
/// train here" — wired in R4.6. UI-only for now; a real notification
/// scheduler is out of scope for this release.
enum ClubNotifyStore {
    private static let key = "clubNotifyOptedIn.v1"
    static func load() -> Set<UUID> {
        let strs = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        return Set(strs.compactMap(UUID.init))
    }
    static func save(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map(\.uuidString), forKey: key)
    }
}

/// R5.5 — Word-of-mouth attribution. When a friend explicitly shares a
/// club with the user (via Share Sheet → "X recommended this"), we
/// stash the (clubId → sharerName) mapping here. The hero eyebrow and
/// rich-card decoration read from it. Demo-seeded with a couple of
/// entries so the surface renders without a real share flow yet.
final class SharedClubStore: ObservableObject {
    static let shared = SharedClubStore()

    private let key = "sharedClubAttribution.v1"
    @Published private var map: [UUID: String]

    init() {
        if let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: String] {
            var m: [UUID: String] = [:]
            for (k, v) in raw {
                if let id = UUID(uuidString: k) { m[id] = v }
            }
            self.map = m
        } else {
            self.map = [:]
        }
    }

    func sharer(for clubId: UUID) -> String? { map[clubId] }

    func recordShare(clubId: UUID, sharerName: String) {
        map[clubId] = sharerName
        persist()
    }

    func dismiss(clubId: UUID) {
        map.removeValue(forKey: clubId)
        persist()
    }

    private func persist() {
        let raw = Dictionary(uniqueKeysWithValues: map.map { ($0.key.uuidString, $0.value) })
        UserDefaults.standard.set(raw, forKey: key)
    }

    /// Demo seed — pick a couple of recommended (non-joined) clubs and
    /// attribute them to fake friends so the word-of-mouth surface is
    /// never empty. Idempotent on a sentinel UserDefaults key.
    static func seedIfNeeded(allClubs: [Club], userClubIds: Set<UUID>) {
        let sentinel = "sharedClubAttributionSeeded.v1"
        guard !UserDefaults.standard.bool(forKey: sentinel) else { return }
        let nonJoined = allClubs.filter { !userClubIds.contains($0.id) }
        let friendNames = SocialSeeder.fakeUsers.prefix(4).map(\.name)
        let attributions = zip(nonJoined.prefix(2), friendNames).map { (club: $0.0, sharer: $0.1) }
        for a in attributions {
            shared.recordShare(clubId: a.club.id, sharerName: a.sharer)
        }
        UserDefaults.standard.set(true, forKey: sentinel)
    }
}

private extension View {
    /// `.scrollTargetBehavior(.paging)` is iOS 17+ and was renamed in
    /// later betas — wrap so older SDKs build cleanly.
    @ViewBuilder
    func scrollTargetBehaviorIfAvailable() -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            self.scrollTargetBehavior(.paging)
        } else {
            self
        }
    }

    /// Force dark color scheme for the Watch surface — the Reels feed
    /// looks broken in light mode.
    @ViewBuilder
    func preferredColorSchemeIfPossible(_ scheme: ColorScheme) -> some View {
        self.preferredColorScheme(scheme)
    }
}

// MARK: - Release 6: Quick-create sheets + anonymous browsing

/// R6 menu — entry into camera, voice, event, post creation. Four big
/// tappable cards in one short sheet. Each callback dismisses the menu;
/// the parent presents the actual mode sheet on a small delay so iOS
/// has time to dismiss the menu before the next sheet animates in.
struct QuickCreateMenuSheet: View {
    let onCamera: () -> Void
    let onVoice: () -> Void
    let onEvent: () -> Void
    let onPost: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Share something")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(GQColors.textPrimary)
            Text("No caption required. The fastest path to being part of the moment.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(GQColors.textTertiary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                quickCard(icon: "camera.fill", title: "Camera", subtitle: "Photo or 5s clip", action: onCamera)
                quickCard(icon: "waveform", title: "Voice", subtitle: "10–30s note", action: onVoice)
                quickCard(icon: "calendar.badge.plus", title: "Event", subtitle: "Anyone want to lift?", action: onEvent)
                quickCard(icon: "square.and.pencil", title: "Post", subtitle: "Write something", action: onPost)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickCard(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(GQGradients.primary.opacity(0.10))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(GQGradients.primary)
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(GQColors.adaptiveOverlay(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(GQColors.borderDefault, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// R6.1 — Camera-first quick capture (mock). The real impl would route
/// into AVCapture. For now we surface the user-facing flow: a faux
/// capture stage with a record/photo button + a confirm step that
/// inserts a ClubPost.
struct CameraQuickCaptureSheet: View {
    let club: Club
    let profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var captured: Bool = false

    var body: some View {
        ZStack {
            // Stand-in viewfinder
            LinearGradient(
                colors: [Color.black, GQColors.deepBlue.opacity(0.4), Color.black],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    Spacer()
                    Text(captured ? "Looks good?" : "Quick capture")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 22))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(20)

                Spacer()

                if !captured {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 80, weight: .ultraLight))
                            .foregroundColor(.white.opacity(0.5))
                        Text("Tap once for photo · hold for 5s clip")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                } else {
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [GQColors.deepBlue, GQColors.vividPurple],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 200, height: 280)
                            Image(systemName: club.resolvedCategory.icon)
                                .font(.system(size: 80, weight: .semibold))
                                .foregroundColor(.white.opacity(0.85))
                        }
                        Text("Captured · ready to share")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.85))
                    }
                }

                Spacer()

                if captured {
                    HStack(spacing: 14) {
                        Button {
                            withAnimation { captured = false }
                        } label: {
                            Text("Retake")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 12)
                                .background(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        Button {
                            sharePost()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Share to club")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(GQColors.deepBlue)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(.white))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 30)
                } else {
                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        #endif
                        withAnimation { captured = true }
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 78, height: 78)
                            Circle()
                                .fill(Color.white)
                                .frame(width: 64, height: 64)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func sharePost() {
        let post = ClubPost(
            clubId: club.id,
            authorId: profile.id,
            authorName: profile.name,
            authorUsername: profile.username,
            postType: .general,
            content: "",
            timestamp: Date()
        )
        modelContext.insert(post)
        try? modelContext.save()
        dismiss()
    }
}

/// R6.2 — Voice-note record sheet. Mock waveform animation, simulated
/// timer. On finish, inserts a ClubPost with a special voice marker in
/// the content body so the timeline cell can render an audio chip.
struct VoiceNotePostSheet: View {
    let club: Club
    let profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isRecording = false
    @State private var elapsed: Double = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(GQColors.textSecondary)
                }
                Spacer()
                Text("Voice note · \(club.name)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
                Spacer()
                Image(systemName: "xmark").opacity(0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)

            Spacer()

            // Waveform stand-in
            HStack(spacing: 3) {
                ForEach(0..<28, id: \.self) { i in
                    let h = barHeight(for: i)
                    Capsule()
                        .fill(isRecording
                            ? AnyShapeStyle(GQGradients.primary)
                            : AnyShapeStyle(GQColors.adaptiveOverlay(0.15)))
                        .frame(width: 4, height: h)
                }
            }
            .frame(height: 56)
            .animation(.easeInOut(duration: 0.18), value: elapsed)

            Text(formatElapsed(elapsed))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(GQColors.textPrimary)
                .monospacedDigit()

            Text(isRecording ? "Recording · tap to stop" : (elapsed > 0 ? "Tap to send" : "Tap to record · 30s max"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(GQColors.textTertiary)

            Spacer()

            HStack(spacing: 16) {
                if elapsed > 0 && !isRecording {
                    Button {
                        elapsed = 0
                    } label: {
                        Text("Discard")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(GQColors.textSecondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Capsule().stroke(GQColors.borderDefault, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                Button { toggleRecord() } label: {
                    ZStack {
                        Circle()
                            .fill(isRecording
                                ? AnyShapeStyle(GQColors.coralRed)
                                : AnyShapeStyle(GQGradients.primary))
                            .frame(width: 64, height: 64)
                        Image(systemName: isRecording ? "stop.fill" : (elapsed > 0 ? "paperplane.fill" : "mic.fill"))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .background(GQColors.background.ignoresSafeArea())
        .onDisappear { timer?.invalidate() }
    }

    private func barHeight(for index: Int) -> CGFloat {
        if isRecording {
            // Random-ish bouncing during record
            let phase = sin(Double(index) * 0.5 + elapsed * 4)
            return CGFloat(20 + abs(phase) * 32)
        }
        if elapsed > 0 {
            // Fixed pattern for the captured note
            let phases: [CGFloat] = [12, 18, 26, 32, 22, 14, 24, 30, 38, 28, 18, 22, 30, 36, 28]
            return phases[index % phases.count]
        }
        return 8
    }

    private func formatElapsed(_ t: Double) -> String {
        let total = Int(t)
        return String(format: "0:%02d", total)
    }

    private func toggleRecord() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        if isRecording {
            isRecording = false
            timer?.invalidate()
        } else if elapsed > 0 {
            // Send
            sendVoiceNote()
        } else {
            isRecording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                elapsed += 0.1
                if elapsed >= 30 {
                    isRecording = false
                    timer?.invalidate()
                }
            }
        }
    }

    private func sendVoiceNote() {
        let caption = VoiceCaptionBank.random()
        let post = ClubPost(
            clubId: club.id,
            authorId: profile.id,
            authorName: profile.name,
            authorUsername: profile.username,
            postType: .general,
            content: "🎙 Voice note · \(formatElapsed(elapsed))\n“\(caption)”",
            timestamp: Date()
        )
        modelContext.insert(post)
        try? modelContext.save()
        dismiss()
    }
}

/// Stub caption bank for voice-note auto-transcription. Real impl would
/// use Apple Speech / on-device whisper.
enum VoiceCaptionBank {
    static let lines: [String] = [
        "Anyone up for a 6 PM session at the ARC?",
        "Just hit a deadlift PR — 365 for 3.",
        "Heading there in 10, save me a bench.",
        "Long ride tomorrow morning, who's in?",
        "Cardio first, then heavy squats. Wish me luck.",
        "Bringing a friend on Friday — first time lifter.",
        "Thinking we move chest day to Wednesday this week.",
        "Just left, the gym is empty right now if anyone wants in."
    ]
    static func random() -> String {
        lines.randomElement() ?? lines[0]
    }
}

// MARK: - Stock-media library + seeder

/// Bundled stock photos under Resources/StockMedia/. Categorized so
/// posts in a Run Club use running shots, lifting clubs use lifting
/// shots, etc. Cover banners are 16:9; post photos are square.
@MainActor
enum StockMediaLibrary {
    /// Map from a category bucket → list of post-photo asset names.
    static let postsByBucket: [String: [String]] = [
        "lift":     ["lift-01", "lift-03", "lift-04", "lift-06", "lift-07", "lift-08"],
        "run":      ["run-01", "run-02", "run-03", "run-04", "run-05", "run-06", "run-07"],
        "yoga":     ["yoga-01", "yoga-02", "yoga-03", "yoga-04", "yoga-05", "yoga-06"],
        "sport":    ["sport-01", "sport-02", "sport-03", "sport-04", "sport-05", "sport-06"],
        "bike":     ["bike-01", "bike-02", "bike-03", "bike-04"],
        "crossfit": ["crossfit-01", "crossfit-02", "crossfit-04"],
        "gym":      ["gym-01", "gym-02", "gym-03", "gym-04"]
    ]

    /// Cover banners — same buckets, but 16:9.
    static let coversByBucket: [String: String] = [
        "lift":     "cover-lift",
        "run":      "cover-run",
        "yoga":     "cover-yoga",
        "sport":    "cover-basketball",
        "bike":     "cover-cycling",
        "crossfit": "cover-crossfit",
        "gym":      "cover-gym",
        "cardio":   "cover-cardio",
        "flow":     "cover-flow",
        "team":     "cover-sport"
    ]

    static func bucket(for category: ClubCategory) -> String {
        switch category {
        case .weightlifting:                            return "lift"
        case .running:                                  return "run"
        case .yoga, .dance:                             return "yoga"
        case .basketball, .soccer, .tennis,
             .volleyball, .hockey, .martialArts:        return "sport"
        case .cycling:                                  return "bike"
        case .crossfit, .hiit:                          return "crossfit"
        case .swimming, .climbing, .generalFitness:     return "gym"
        }
    }

    /// Returns Data for a bundled image, looking under
    /// `Resources/StockMedia/posts/<name>.jpg` or `covers/`.
    static func data(named name: String, in subdir: String) -> Data? {
        guard let url = Bundle.main.url(
            forResource: name,
            withExtension: "jpg",
            subdirectory: "StockMedia/\(subdir)"
        ) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Pick a deterministic post photo for (club, postIndex). Stable
    /// per (club, index) so re-renders return the same image.
    static func postPhoto(for club: Club, index: Int) -> Data? {
        let bucket = bucket(for: club.resolvedCategory)
        let names = postsByBucket[bucket] ?? postsByBucket["gym"] ?? []
        guard !names.isEmpty else { return nil }
        let seed = abs(club.id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        let pick = names[(seed + index) % names.count]
        return data(named: pick, in: "posts")
    }

    static func coverPhoto(for club: Club) -> Data? {
        let bucket = bucket(for: club.resolvedCategory)
        let name = coversByBucket[bucket] ?? "cover-gym"
        return data(named: name, in: "covers")
    }
}

// MARK: - Real-photo media seeder

/// One-time seeder that fills non-joined clubs with photo + video posts
/// so the media-driven discovery surfaces (Snapshots, Watch, Cinema,
/// hero backdrops, rich-card thumbnails) render real-looking content
/// instead of category-gradient placeholders.
///
/// Pulls from the bundled Resources/StockMedia/ photo set, picking
/// images by club category. Each non-joined club also gets a 16:9
/// cover banner stored on Club.imageData.
@MainActor
enum ClubMediaSeeder {
    private static let sentinelKey = "clubFakeMediaSeeded.v2"

    /// Captions paired with a hint about whether the post should read
    /// as a "video" (we render a play indicator on top of the photo).
    private static let captions: [(text: String, isVideo: Bool)] = [
        ("Heavy back day · 5×5 squats came in clean", false),
        ("Quick warmup edit from this morning", true),
        ("Trail run views were 🔥 today", false),
        ("Pad work session — tempo's getting better", true),
        ("3v3 finals tonight, doors at 7", false),
        ("Saturday long ride: 80km out + back", false),
        ("Recovery flow before the lift session", false),
        ("New PR alert — pulled 405 for the first time", true),
        ("Open gym vibes, anyone want to lift?", false),
        ("HIIT class was brutal in the best way", true),
        ("Climbing nights getting busy — get on the wall", false),
        ("Ride to the ferry + coffee stop, weekend regular", false)
    ]

    static func seedIfNeeded(modelContext: ModelContext, allClubs: [Club], userClubIds: Set<UUID>) {
        guard !UserDefaults.standard.bool(forKey: sentinelKey) else { return }

        // Wipe v1 procedural posts so the surface refills cleanly with
        // real photos. Detect by content prefix from the v1 seeder.
        let allPostsDesc = FetchDescriptor<ClubPost>()
        if let existing = try? modelContext.fetch(allPostsDesc) {
            for post in existing where post.content.hasPrefix("📸 ") || post.content.hasPrefix("🎥 ") {
                modelContext.delete(post)
            }
        }

        let nonJoined = allClubs.filter { !userClubIds.contains($0.id) }
        let users = SocialSeeder.fakeUsers
        let now = Date()

        // Cover banner first — set Club.imageData so detail-page hero
        // and any cover-aware card can render the wide photo.
        for club in nonJoined {
            if club.imageData == nil, let cover = StockMediaLibrary.coverPhoto(for: club) {
                club.imageData = cover
            }
        }

        var generated = 0
        for club in nonJoined.prefix(12) {
            // 5 posts per club: 4 photos + 1 "video"
            for i in 0..<5 {
                let captionPair = captions[(generated + i) % captions.count]
                let isVideo = i == 4 || captionPair.isVideo
                let user = users[(generated + i) % users.count]
                let daysAgo = Double(generated + i).truncatingRemainder(dividingBy: 14) + 0.3
                let timestamp = now.addingTimeInterval(-daysAgo * 24 * 3600)

                let imageData = StockMediaLibrary.postPhoto(for: club, index: generated * 7 + i)

                let prefix = isVideo ? "🎥 " : "📸 "
                let post = ClubPost(
                    clubId: club.id,
                    authorId: user.id,
                    authorName: user.name,
                    authorUsername: user.username,
                    postType: .general,
                    content: prefix + captionPair.text,
                    photoData: imageData,
                    likeCount: Int.random(in: 4...64),
                    commentCount: Int.random(in: 0...12),
                    timestamp: timestamp
                )
                modelContext.insert(post)
                generated += 1
            }
        }

        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: sentinelKey)
    }

    /// Render one procedural photo for a post. 800×800, baseline
    /// gradient + big SF-symbol subject + corner badges (caption +
    /// author initial + play glyph for videos).
    private static func renderProceduralPhoto(
        club: Club,
        seed: Int,
        isVideo: Bool,
        caption: String
    ) -> Data? {
        #if canImport(UIKit)
        let size = CGSize(width: 800, height: 800)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            drawProceduralPhoto(
                in: ctx.cgContext,
                size: size,
                club: club,
                seed: seed,
                isVideo: isVideo,
                caption: caption
            )
        }
        return img.pngData()
        #else
        return nil
        #endif
    }

    #if canImport(UIKit)
    /// Drawing pipeline. Kept self-contained so other surfaces can
    /// reuse the same look if needed (e.g. user-uploaded fallbacks).
    private static func drawProceduralPhoto(
        in cg: CGContext,
        size: CGSize,
        club: Club,
        seed: Int,
        isVideo: Bool,
        caption: String
    ) {
        // 1) Diagonal gradient base.
        let palette = palette(for: club.resolvedCategory, seed: seed)
        let cs = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(
            colorsSpace: cs,
            colors: palette.map { $0.cgColor } as CFArray,
            locations: [0.0, 0.55, 1.0]
        )!
        cg.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: size.width, y: size.height),
            options: []
        )

        // 2) Soft radial highlight (off-center based on seed).
        let hx = 0.25 + (CGFloat(seed % 5) * 0.12)
        let hy = 0.20 + (CGFloat((seed / 5) % 5) * 0.10)
        let highlight = CGGradient(
            colorsSpace: cs,
            colors: [
                UIColor.white.withAlphaComponent(0.30).cgColor,
                UIColor.white.withAlphaComponent(0.0).cgColor
            ] as CFArray,
            locations: [0.0, 1.0]
        )!
        cg.drawRadialGradient(
            highlight,
            startCenter: CGPoint(x: size.width * hx, y: size.height * hy),
            startRadius: 0,
            endCenter: CGPoint(x: size.width * hx, y: size.height * hy),
            endRadius: size.width * 0.55,
            options: []
        )

        // 3) Big SF-symbol subject.
        let cfg = UIImage.SymbolConfiguration(pointSize: 320, weight: .bold)
        if let symbol = UIImage(systemName: club.resolvedCategory.icon, withConfiguration: cfg)?
            .withTintColor(UIColor.white.withAlphaComponent(0.32), renderingMode: .alwaysOriginal)
        {
            let symRect = CGRect(
                x: (size.width - symbol.size.width) / 2,
                y: (size.height - symbol.size.height) / 2 + 40,
                width: symbol.size.width,
                height: symbol.size.height
            )
            symbol.draw(in: symRect)
        }

        // 4) Bottom-left text badge — caption + club caps line.
        drawTextBadge(in: cg, size: size, caption: caption, club: club)

        // 5) Top-right play indicator for video posts.
        if isVideo {
            drawPlayBadge(in: cg, size: size)
        }
    }

    private static func drawTextBadge(
        in cg: CGContext,
        size: CGSize,
        caption: String,
        club: Club
    ) {
        let captionFont = UIFont.systemFont(ofSize: 28, weight: .semibold)
        let clubFont = UIFont.systemFont(ofSize: 16, weight: .heavy)

        let captionAttrs: [NSAttributedString.Key: Any] = [
            .font: captionFont,
            .foregroundColor: UIColor.white,
            .kern: 0.2
        ]
        let clubAttrs: [NSAttributedString.Key: Any] = [
            .font: clubFont,
            .foregroundColor: UIColor.white.withAlphaComponent(0.85),
            .kern: 1.6
        ]

        let captionStr = NSAttributedString(string: caption, attributes: captionAttrs)
        let clubStr = NSAttributedString(string: club.name.uppercased(), attributes: clubAttrs)

        // Bottom-aligned with breathing room.
        let captionMaxWidth = size.width - 80
        let captionRect = captionStr.boundingRect(
            with: CGSize(width: captionMaxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            context: nil
        )

        let captionOrigin = CGPoint(x: 40, y: size.height - 40 - captionRect.height)
        let clubOrigin = CGPoint(x: 40, y: captionOrigin.y - 30)

        clubStr.draw(at: clubOrigin)
        captionStr.draw(in: CGRect(
            x: captionOrigin.x,
            y: captionOrigin.y,
            width: captionMaxWidth,
            height: captionRect.height + 8
        ))
    }

    private static func drawPlayBadge(in cg: CGContext, size: CGSize) {
        let badgeRect = CGRect(x: size.width - 110, y: 40, width: 70, height: 70)
        cg.saveGState()
        cg.setFillColor(UIColor.black.withAlphaComponent(0.45).cgColor)
        cg.addEllipse(in: badgeRect)
        cg.fillPath()
        cg.restoreGState()

        // Triangle play glyph
        let cfg = UIImage.SymbolConfiguration(pointSize: 32, weight: .bold)
        if let play = UIImage(systemName: "play.fill", withConfiguration: cfg)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        {
            let pr = CGRect(
                x: badgeRect.midX - play.size.width / 2 + 3,
                y: badgeRect.midY - play.size.height / 2,
                width: play.size.width,
                height: play.size.height
            )
            play.draw(in: pr)
        }
    }

    /// Per-category color palette + seed-driven variation so successive
    /// posts in the same club don't all look identical.
    private static func palette(for category: ClubCategory, seed: Int) -> [UIColor] {
        let base: [(top: UIColor, mid: UIColor, end: UIColor)]
        switch category {
        case .running, .cycling, .swimming:
            base = [
                (UIColor(red: 0.20, green: 0.82, blue: 1.00, alpha: 1),
                 UIColor(red: 0.24, green: 0.49, blue: 1.00, alpha: 1),
                 UIColor(red: 0.05, green: 0.10, blue: 0.30, alpha: 1)),
                (UIColor(red: 0.40, green: 0.85, blue: 0.95, alpha: 1),
                 UIColor(red: 0.16, green: 0.45, blue: 0.72, alpha: 1),
                 UIColor(red: 0.04, green: 0.08, blue: 0.18, alpha: 1)),
            ]
        case .weightlifting, .crossfit, .hiit:
            base = [
                (UIColor(red: 0.79, green: 0.36, blue: 1.00, alpha: 1),
                 UIColor(red: 0.42, green: 0.27, blue: 0.95, alpha: 1),
                 UIColor(red: 0.10, green: 0.04, blue: 0.20, alpha: 1)),
                (UIColor(red: 1.00, green: 0.42, blue: 0.62, alpha: 1),
                 UIColor(red: 0.65, green: 0.20, blue: 0.55, alpha: 1),
                 UIColor(red: 0.10, green: 0.05, blue: 0.18, alpha: 1)),
            ]
        case .basketball, .soccer, .tennis, .volleyball, .hockey:
            base = [
                (UIColor(red: 1.00, green: 0.55, blue: 0.30, alpha: 1),
                 UIColor(red: 0.96, green: 0.30, blue: 0.50, alpha: 1),
                 UIColor(red: 0.18, green: 0.05, blue: 0.20, alpha: 1)),
                (UIColor(red: 1.00, green: 0.78, blue: 0.20, alpha: 1),
                 UIColor(red: 0.95, green: 0.42, blue: 0.20, alpha: 1),
                 UIColor(red: 0.18, green: 0.08, blue: 0.10, alpha: 1)),
            ]
        case .yoga, .dance, .climbing:
            base = [
                (UIColor(red: 0.55, green: 1.00, blue: 0.78, alpha: 1),
                 UIColor(red: 0.28, green: 0.65, blue: 1.00, alpha: 1),
                 UIColor(red: 0.10, green: 0.10, blue: 0.30, alpha: 1)),
                (UIColor(red: 0.95, green: 0.65, blue: 0.95, alpha: 1),
                 UIColor(red: 0.45, green: 0.40, blue: 0.95, alpha: 1),
                 UIColor(red: 0.08, green: 0.05, blue: 0.20, alpha: 1)),
            ]
        case .martialArts:
            base = [
                (UIColor(red: 1.00, green: 0.35, blue: 0.30, alpha: 1),
                 UIColor(red: 0.50, green: 0.10, blue: 0.20, alpha: 1),
                 UIColor.black),
            ]
        case .generalFitness:
            base = [
                (UIColor(red: 0.30, green: 0.55, blue: 1.00, alpha: 1),
                 UIColor(red: 0.55, green: 0.40, blue: 1.00, alpha: 1),
                 UIColor(red: 0.05, green: 0.05, blue: 0.20, alpha: 1)),
            ]
        }

        let pick = base[abs(seed) % base.count]
        return [pick.top, pick.mid, pick.end]
    }
    #endif
}

/// R6.5 — Tracks 3-day anonymous browsing windows per club. Stored as
/// `[clubId: startedAt]` in UserDefaults. Active window check is done
/// at render time so the UI naturally rolls off when the window expires.
final class AnonymousBrowsingStore {
    static let shared = AnonymousBrowsingStore()
    private let key = "anonymousBrowsingV1"

    private var map: [UUID: Date] {
        get {
            let raw = UserDefaults.standard.dictionary(forKey: key) as? [String: TimeInterval] ?? [:]
            var m: [UUID: Date] = [:]
            for (k, v) in raw {
                if let id = UUID(uuidString: k) {
                    m[id] = Date(timeIntervalSinceReferenceDate: v)
                }
            }
            return m
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.uuidString, $0.value.timeIntervalSinceReferenceDate) })
            UserDefaults.standard.set(raw, forKey: key)
        }
    }

    func startedAt(for clubId: UUID) -> Date? { map[clubId] }
    func start(for clubId: UUID) {
        var m = map
        m[clubId] = Date()
        map = m
    }
    func end(for clubId: UUID) {
        var m = map
        m.removeValue(forKey: clubId)
        map = m
    }
}

// MARK: - Release 7: Music & Media (Soundtrack of the page)

/// Mood/energy bucket for a track. Drives the mood ring color around
/// avatars + the dominant-color picker for the cinema overlay.
enum TrackMood: String, CaseIterable, Hashable {
    case hype, focus, chill, recovery, rage

    var color: Color {
        switch self {
        case .hype:     return GQColors.coralRed
        case .focus:    return GQColors.deepBlue
        case .chill:    return GQColors.cyanSpark
        case .recovery: return GQColors.vividPurple
        case .rage:     return GQColors.electricGold
        }
    }

    var label: String {
        switch self {
        case .hype:     return "Hype"
        case .focus:    return "Focus"
        case .chill:    return "Chill"
        case .recovery: return "Recovery"
        case .rage:     return "Rage"
        }
    }
}

struct Track: Hashable, Identifiable {
    let id: String
    let title: String
    let artist: String
    let mood: TrackMood
    let bpm: Int
}

/// Demo-grade soundtrack mapping. A curated track bank + deterministic
/// per-club playlist derived from category. Real impl would pull from
/// a Spotify/Apple Music link table per club.
enum ClubSoundtrackLibrary {
    static let bank: [Track] = [
        Track(id: "k-power",        title: "Power",                artist: "Kanye West",        mood: .hype,     bpm: 156),
        Track(id: "k-stronger",     title: "Stronger",             artist: "Kanye West",        mood: .hype,     bpm: 152),
        Track(id: "weeknd-blinding",title: "Blinding Lights",      artist: "The Weeknd",        mood: .hype,     bpm: 171),
        Track(id: "kendrick-humble",title: "HUMBLE.",              artist: "Kendrick Lamar",    mood: .rage,     bpm: 150),
        Track(id: "tyler-see-you",  title: "See You Again",        artist: "Tyler, the Creator",mood: .focus,    bpm: 160),
        Track(id: "drake-energy",   title: "Energy",               artist: "Drake",             mood: .rage,     bpm: 175),
        Track(id: "skrillex-bangarang", title: "Bangarang",        artist: "Skrillex",          mood: .hype,     bpm: 110),
        Track(id: "fka-cellophane", title: "Cellophane",           artist: "FKA twigs",         mood: .recovery, bpm: 82),
        Track(id: "frank-pyramids", title: "Pyramids",             artist: "Frank Ocean",       mood: .focus,    bpm: 80),
        Track(id: "tame-let-it-happen", title: "Let It Happen",    artist: "Tame Impala",       mood: .focus,    bpm: 119),
        Track(id: "billie-bury-friend", title: "Bury a Friend",    artist: "Billie Eilish",     mood: .recovery, bpm: 120),
        Track(id: "lana-summertime", title: "Summertime Sadness",  artist: "Lana Del Rey",      mood: .chill,    bpm: 153),
        Track(id: "post-circles",   title: "Circles",              artist: "Post Malone",       mood: .chill,    bpm: 120),
        Track(id: "nas-it-aint-hard", title: "It Ain't Hard to Tell", artist: "Nas",            mood: .focus,    bpm: 84),
        Track(id: "rage-killing",   title: "Killing in the Name",  artist: "Rage Against the Machine", mood: .rage, bpm: 92),
        Track(id: "lizzo-good",     title: "Good as Hell",         artist: "Lizzo",             mood: .hype,     bpm: 95),
        Track(id: "phoebe-motion",  title: "Motion Sickness",      artist: "Phoebe Bridgers",   mood: .recovery, bpm: 96),
        Track(id: "tyler-eartha",   title: "EARFQUAKE",            artist: "Tyler, the Creator",mood: .chill,    bpm: 80),
        Track(id: "metro-trance",   title: "Trance",               artist: "Metro Boomin",      mood: .focus,    bpm: 144),
        Track(id: "sza-good-days",  title: "Good Days",            artist: "SZA",               mood: .chill,    bpm: 121),
    ]

    /// Map a club category to a primary mood. Used to bias track
    /// selection — a powerlifting club gets more rage/hype, yoga gets
    /// recovery, running gets focus, etc.
    static func categoryMood(_ category: ClubCategory) -> TrackMood {
        switch category {
        case .weightlifting, .crossfit, .hiit, .martialArts:
            return .rage
        case .basketball, .soccer, .tennis, .volleyball, .hockey:
            return .hype
        case .running, .cycling, .swimming:
            return .focus
        case .yoga, .dance:
            return .recovery
        case .climbing:
            return .focus
        case .generalFitness:
            return .hype
        }
    }

    /// 4–5 track playlist for a club. Deterministic by id + biased
    /// toward the category's primary mood.
    static func soundtrack(for club: Club) -> [Track] {
        let primary = categoryMood(club.resolvedCategory)
        let primaryTracks = bank.filter { $0.mood == primary }
        let secondaryTracks = bank.filter { $0.mood != primary }
        let seed = abs(club.id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })

        // Deterministic shuffle: rotate by seed, take 3 primary + 2 others.
        let p = rotated(primaryTracks, by: seed)
        let s = rotated(secondaryTracks, by: seed / 7)
        let pickedPrimary = Array(p.prefix(3))
        let pickedSecondary = Array(s.prefix(2))
        return pickedPrimary + pickedSecondary
    }

    /// The club's dominant mood — drives the mood ring color.
    static func mood(for club: Club) -> TrackMood {
        let counts = Dictionary(grouping: soundtrack(for: club), by: \.mood)
            .mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key ?? categoryMood(club.resolvedCategory)
    }

    /// Walk-in track for an event — first track of the host club's
    /// soundtrack, rotated by event id so different events get
    /// different opening songs.
    static func warmupTrack(for event: ClubEvent, club: Club) -> Track {
        let s = soundtrack(for: club)
        let seed = abs(event.id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        let idx = s.isEmpty ? 0 : seed % max(1, s.count)
        return s[idx]
    }

    /// Track a member is currently lifting to — deterministic by user
    /// id so it's stable across rerenders. Real impl would tap into
    /// MusicKit "Now Playing".
    static func nowPlaying(for userId: UUID) -> Track {
        let seed = abs(userId.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
        return bank[seed % bank.count]
    }

    private static func rotated<T>(_ array: [T], by amount: Int) -> [T] {
        guard !array.isEmpty else { return array }
        let n = amount % array.count
        return Array(array[n...] + array[..<n])
    }
}

// MARK: - R7 view helpers

/// Animated equalizer + label combo. Used wherever the app needs to
/// signal "audio is happening here": live stream cards, now-playing
/// rows, watch waveforms.
struct TrackEqualizerView: View {
    let bars: Int
    let height: CGFloat
    let color: Color

    init(bars: Int = 5, height: CGFloat = 12, color: Color = .white) {
        self.bars = bars
        self.height = height
        self.color = color
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<bars, id: \.self) { i in
                    let phase = sin(t * 4 + Double(i) * 0.7) * 0.5 + 0.5
                    Capsule()
                        .fill(color)
                        .frame(width: 2.5, height: max(2, height * 0.3 + height * CGFloat(phase) * 0.7))
                }
            }
        }
        .frame(width: CGFloat(bars) * 5, height: height)
    }
}

/// Walk-in music chip for event date cards. Translucent dark capsule
/// with ♪ + track + artist.
struct WalkInMusicChip: View {
    let track: Track

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "music.note")
                .font(.system(size: 9, weight: .bold))
            Text("\(track.title) · \(track.artist)")
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.32)))
    }
}

/// Mood ring for a club avatar — soft outer glow + thin gradient ring.
/// Sized to wrap a circular avatar by passing the avatar's diameter as
/// `inner`. Outer ring sits a few points beyond.
struct MoodRing: View {
    let mood: TrackMood
    let inner: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(mood.color.opacity(0.28))
                .frame(width: inner + 18, height: inner + 18)
                .blur(radius: 8)
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [mood.color.opacity(0.7), mood.color.opacity(0.3), mood.color.opacity(0.7)],
                        center: .center
                    ),
                    lineWidth: 1.5
                )
                .frame(width: inner + 6, height: inner + 6)
        }
    }
}
