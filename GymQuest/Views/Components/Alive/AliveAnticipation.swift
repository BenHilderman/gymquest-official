//
//  AliveAnticipation.swift
//  GymQuest
//
//  Phase 4 of the Alive release: anticipation + memory.
//  - GlobalLifterCounter: persistent footer "N lifting right now" (deterministic
//    fake number based on hour-of-day so the app never feels empty).
//  - CoPresenceDetector: writes CoPresenceLog when two users' PresenceState
//    had overlapping gymId for ≥30 min. Surfaced via CoAttendedCard.
//  - PreEventCountdownBanner: club-event hero shown ≤6h before start when
//    ≥2 followed friends are attending.
//

import SwiftUI
import SwiftData

// MARK: - Anonymous global counter

enum GlobalLifterCounter {
    /// Pulled from a fake-API stub. Deterministic-per-hour so the number
    /// drifts naturally through the day rather than thrashing every render.
    static func countNow(at date: Date = Date()) -> Int {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let day = cal.component(.day, from: date)
        // Bell curve peak around 6pm + bump around 7am.
        let amBump = max(0, 1500 - abs(hour - 7) * 200)
        let pmBump = max(0, 4500 - abs(hour - 18) * 350)
        let baseline = 1200 + (day % 7) * 60
        return baseline + amBump + pmBump
    }
}

struct GlobalLifterFooter: View {
    var body: some View {
        let count = GlobalLifterCounter.countNow()
        let formatted = count.formatted(.number)
        HStack(spacing: 6) {
            Circle()
                .fill(AlivePresence.green)
                .frame(width: 5, height: 5)
            Text("\(formatted) lifting right now")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(GQColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

// MARK: - Co-attended detector

@MainActor
enum CoPresenceDetector {
    /// Scans recently-finished pairs of presence rows and writes a
    /// `CoPresenceLog` row when their gymIds matched + their session
    /// windows overlapped ≥30 min. Idempotent per pair-of-sessions.
    static func detectAndLog(
        states: [UserPresenceState],
        in modelContext: ModelContext
    ) {
        let finished = states.filter { $0.status == .finishedRecently || ($0.status == .idle && $0.endedAt != nil) }
        guard finished.count >= 2 else { return }
        for i in 0..<finished.count {
            for j in (i+1)..<finished.count {
                let a = finished[i], b = finished[j]
                guard let gymA = a.gymId, gymA == b.gymId,
                      let aStart = a.startedAt, let bStart = b.startedAt else { continue }
                let aEnd = a.endedAt ?? a.updatedAt
                let bEnd = b.endedAt ?? b.updatedAt
                let overlapStart = max(aStart, bStart)
                let overlapEnd = min(aEnd, bEnd)
                let overlap = overlapEnd.timeIntervalSince(overlapStart)
                guard overlap >= 30 * 60 else { continue }

                // Idempotency: skip if a log row for this exact overlap exists.
                let aId = a.userId, bId = b.userId
                let descriptor = FetchDescriptor<CoPresenceLog>(
                    predicate: #Predicate { row in
                        ((row.userIdA == aId && row.userIdB == bId)
                         || (row.userIdA == bId && row.userIdB == aId))
                        && row.overlapStart == overlapStart
                    }
                )
                if let existing = try? modelContext.fetch(descriptor), !existing.isEmpty { continue }

                let log = CoPresenceLog(
                    userIdA: aId,
                    userIdB: bId,
                    gymId: gymA,
                    gymName: a.gymName ?? b.gymName,
                    overlapStart: overlapStart,
                    overlapEnd: overlapEnd
                )
                modelContext.insert(log)
            }
        }
        try? modelContext.save()
    }
}

struct CoAttendedCard: View {
    let log: CoPresenceLog
    let companionName: String
    let myName: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(GQColors.deepBlue.opacity(0.10)).frame(width: 44, height: 44)
                Image(systemName: "figure.2.arms.open")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("CO-ATTENDED")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(GQGradients.primary)
                Text("\(myName) + \(companionName)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                let mins = max(0, Int(log.overlapEnd.timeIntervalSince(log.overlapStart) / 60))
                Text("\(mins) min at \(log.gymName ?? "the gym")")
                    .font(.system(size: 12))
                    .foregroundColor(GQColors.textSecondary)
            }
            Spacer()
        }
        .padding(14)
        .homeSocialCard(cornerRadius: 14)
    }
}

// MARK: - Pre-event countdown banner

struct PreEventCountdownBanner: View {
    let eventTitle: String
    let startsAt: Date
    let attendingFriendCount: Int
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(AlivePresence.gold.opacity(0.18)).frame(width: 44, height: 44)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AlivePresence.gold)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(eventTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                    Text("\(timeUntil) · \(attendingFriendCount) friend\(attendingFriendCount == 1 ? "" : "s") going")
                        .font(.system(size: 12))
                        .foregroundColor(GQColors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
            }
            .padding(14)
            .homeSocialCard(cornerRadius: 14)
        }
        .buttonStyle(.plain)
    }

    private var timeUntil: String {
        let secs = Int(startsAt.timeIntervalSince(Date()))
        if secs <= 0 { return "now" }
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "in \(h)h \(m)m" }
        return "in \(m)m"
    }
}

// MARK: - Sunday weekly crew recap

struct SundayCrewRecap {
    let crewSessions: Int
    let withYouSessions: Int
}

@MainActor
enum SundayCrewRecapResolver {
    /// Returns the recap when today is Sunday and there's enough signal
    /// to render it (>= 3 crew sessions in the last 7 days). Otherwise nil.
    static func recap(
        myUserId: UUID,
        followedIds: Set<UUID>,
        checkIns: [WorkoutCheckIn],
        coPresence: [CoPresenceLog],
        now: Date = Date()
    ) -> SundayCrewRecap? {
        let cal = Calendar.current
        guard cal.component(.weekday, from: now) == 1 else { return nil }
        let weekStart = cal.date(byAdding: .day, value: -7, to: cal.startOfDay(for: now))!
        let crewSessions = checkIns.filter {
            followedIds.contains($0.userId) && $0.timestamp >= weekStart
        }.count
        let withYouSessions = coPresence.filter {
            ($0.userIdA == myUserId || $0.userIdB == myUserId)
            && $0.overlapEnd >= weekStart
        }.count
        guard crewSessions >= 3 else { return nil }
        return SundayCrewRecap(
            crewSessions: crewSessions,
            withYouSessions: withYouSessions
        )
    }
}

struct SundayCrewRecapCard: View {
    let recap: SundayCrewRecap

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(GQColors.deepBlue.opacity(0.10)).frame(width: 44, height: 44)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("THIS WEEK · YOUR CREW")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(GQGradients.primary)
                Text("\(recap.crewSessions) sessions · \(recap.withYouSessions) with you")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
            }
            Spacer()
        }
        .padding(14)
        .homeSocialCard(cornerRadius: 14)
    }
}

// MARK: - Streak alarm (friend's streak ending in <4h)

struct StreakAlarmCandidate: Identifiable {
    let id: UUID    // userId
    let name: String
    let hoursLeft: Int
}

@MainActor
enum StreakAlarmResolver {
    /// Returns at most one candidate per scan to keep the prompt small.
    /// Approximation: looks for followed users whose last check-in was
    /// 20–24h ago (their streak will lapse in <4h if they haven't trained
    /// today). One per friend per day — gated by PushThrottle.
    static func candidate(
        followedIds: Set<UUID>,
        userProfiles: [UserProfile],
        checkIns: [WorkoutCheckIn],
        now: Date = Date()
    ) -> StreakAlarmCandidate? {
        let dayAgo = now.addingTimeInterval(-20 * 3600)
        let cutoff = now.addingTimeInterval(-24 * 3600)
        let lastByUser = Dictionary(grouping: checkIns.filter { followedIds.contains($0.userId) }, by: \.userId)
            .compactMapValues { $0.max(by: { $0.timestamp < $1.timestamp }) }
        let candidate = lastByUser.first(where: { _, last in
            last.timestamp >= cutoff && last.timestamp < dayAgo
        })
        guard let (userId, last) = candidate else { return nil }
        guard PushThrottle.canPush(forFriend: userId, on: now) else { return nil }
        let name = userProfiles.first(where: { $0.id == userId })?.name
            ?? SocialSeeder.fakeUsers.first(where: { $0.id == userId })?.name
            ?? "Your friend"
        let hoursLeft = max(1, 4 - Int((now.timeIntervalSince(last.timestamp) - 20 * 3600) / 3600))
        return StreakAlarmCandidate(id: userId, name: name, hoursLeft: hoursLeft)
    }
}

struct StreakAlarmCard: View {
    let candidate: StreakAlarmCandidate
    let fromUserId: UUID

    @Environment(\.modelContext) private var modelContext
    @State private var didNudge: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(AlivePresence.gold.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: "flame.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AlivePresence.gold)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(candidate.name)'s streak ends in \(candidate.hoursLeft)h")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Text("Send a nudge?")
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textSecondary)
            }
            Spacer()
            Button {
                nudge()
            } label: {
                Text(didNudge ? "Sent ✓" : "Nudge")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(didNudge ? AnyShapeStyle(AlivePresence.green) : AnyShapeStyle(GQGradients.primary)))
            }
            .buttonStyle(.plain)
            .disabled(didNudge)
        }
        .padding(14)
        .homeSocialCard(cornerRadius: 14)
    }

    private func nudge() {
        let r = LiveReaction(
            fromUserId: fromUserId,
            toUserId: candidate.id,
            sessionStartedAt: Date(),
            kind: "stat",
            statText: "Don't break it 🔥"
        )
        modelContext.insert(r)
        try? modelContext.save()
        PushThrottle.recordPush(forFriend: candidate.id)
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { didNudge = true }
    }
}

@MainActor
enum PreEventResolver {
    struct Match: Identifiable {
        let id: UUID
        let title: String
        let startsAt: Date
        let attendingFriendCount: Int
    }

    /// Returns events the user's joined clubs have starting in <= 6h with
    /// >= 2 followed friends in the attendees list.
    static func upcoming(
        myUserId: UUID,
        followedIds: Set<UUID>,
        myClubIds: Set<UUID>,
        events: [ClubEvent]
    ) -> [Match] {
        let now = Date()
        let horizon = now.addingTimeInterval(6 * 3600)
        return events.compactMap { ev in
            guard myClubIds.contains(ev.clubId) else { return nil }
            guard ev.date > now, ev.date <= horizon else { return nil }
            let attendingFriends = ev.attendeeIds.filter { followedIds.contains($0) }.count
            guard attendingFriends >= 2 else { return nil }
            return Match(id: ev.id, title: ev.title, startsAt: ev.date, attendingFriendCount: attendingFriends)
        }
        .sorted { $0.startsAt < $1.startsAt }
    }
}
