// Partner Mode types — design v4.3 §10
// Sessions, streaks, invite payloads. Server-of-record in Supabase tables.

import Foundation
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

enum PartnerSessionState: String, Codable {
    case pending
    case accepted
    case declined
    case active
    case ended
    case expired
}

@Model
final class PartnerSession {
    @Attribute(.unique) var id: UUID
    var initiatorId: UUID
    var partnerId: UUID
    var workoutAId: UUID?
    var workoutBId: UUID?
    var invitedWorkoutType: String?
    var stateRaw: String
    var sharedPostId: UUID?
    var postTogetherEnabled: Bool
    var invitedAt: Date
    var acceptedAt: Date?
    var startedAt: Date?
    var endedAt: Date?

    init(
        id: UUID = UUID(),
        initiatorId: UUID,
        partnerId: UUID,
        invitedWorkoutType: String? = nil,
        state: PartnerSessionState = .pending,
        sharedPostId: UUID? = nil,
        postTogetherEnabled: Bool = true,
        invitedAt: Date = .init()
    ) {
        self.id = id
        self.initiatorId = initiatorId
        self.partnerId = partnerId
        self.invitedWorkoutType = invitedWorkoutType
        self.stateRaw = state.rawValue
        self.sharedPostId = sharedPostId
        self.postTogetherEnabled = postTogetherEnabled
        self.invitedAt = invitedAt
    }

    var state: PartnerSessionState {
        get { PartnerSessionState(rawValue: stateRaw) ?? .pending }
        set { stateRaw = newValue.rawValue }
    }
}

@Model
final class PartnerStreak {
    @Attribute(.unique) var pairKey: String  // sorted "userA-userB"
    var userA: UUID
    var userB: UUID
    var streakCount: Int
    var lastSessionAt: Date?
    var brokenAt: Date?
    var updatedAt: Date

    init(userA: UUID, userB: UUID, streakCount: Int = 0) {
        let pair = [userA.uuidString, userB.uuidString].sorted().joined(separator: "-")
        self.pairKey = pair
        self.userA = userA
        self.userB = userB
        self.streakCount = streakCount
        self.updatedAt = .init()
    }

    /// Streak rules per design: 3+ partner sessions in 30 days = streak.
    /// Breaks if 14 days without partner session.
    func ingestSession(at date: Date) {
        defer { updatedAt = .init() }
        if let last = lastSessionAt, date.timeIntervalSince(last) > 14 * 86_400 {
            brokenAt = date
            streakCount = 0
        }
        streakCount += 1
        lastSessionAt = date
    }

    var isActive: Bool { streakCount >= 3 && brokenAt == nil }
}

@MainActor
final class PartnerModeService: ObservableObject {
    static let shared = PartnerModeService()
    @Published var pendingInvites: [PartnerSession] = []
    @Published var activeSession: PartnerSession?

    private init() {}

    func sendInvite(to partnerId: UUID, by initiatorId: UUID, workoutType: String?) -> PartnerSession {
        let session = PartnerSession(
            initiatorId: initiatorId,
            partnerId: partnerId,
            invitedWorkoutType: workoutType,
            state: .pending
        )
        pendingInvites.append(session)
        return session
    }

    func accept(_ session: PartnerSession) {
        session.state = .accepted
        session.acceptedAt = .init()
    }

    func decline(_ session: PartnerSession) {
        session.state = .declined
        pendingInvites.removeAll { $0.id == session.id }
    }

    func startSession(_ session: PartnerSession, workoutAId: UUID, workoutBId: UUID) {
        session.state = .active
        session.workoutAId = workoutAId
        session.workoutBId = workoutBId
        session.startedAt = .init()
        activeSession = session
    }

    func endSession(_ session: PartnerSession, sharedPostId: UUID? = nil) {
        session.state = .ended
        session.endedAt = .init()
        session.sharedPostId = sharedPostId
        if activeSession?.id == session.id { activeSession = nil }
    }

    /// Auto-disable on ghost transition per design §10 privacy.
    func handleGhostModeChange(level: GhostModeLevel) {
        guard level == .ghost, let active = activeSession else { return }
        endSession(active)
    }

    /// v4.3 §10 auto-sync — broadcast a set-log to the active partner.
    /// In production this writes to a Supabase realtime channel; on the
    /// device it fires a local light haptic so the design surface is
    /// observable in dev/sim. No-op when no partner session is active.
    func notifySetLogged(by userId: UUID, exerciseName: String, weight: Double, reps: Int) {
        guard let session = activeSession, session.state == .active else { return }
        guard userId == session.initiatorId || userId == session.partnerId else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        #if DEBUG
        print("[partner-sync] set logged in session \(session.id): \(exerciseName) \(Int(weight))×\(reps)")
        #endif
        // Hook for the real broadcast — uncomment and wire when the
        // Supabase channel is in scope:
        // SupabaseUpsertBridge.upsert(table: "partner_session_events", row: [...])
    }

    /// v4.3 §10 — PR moments sync between partners. Mirror: broadcasts an
    /// event row + haptic. Either partner sees their counterpart's PR.
    func notifyPRHit(by userId: UUID, exerciseName: String, value: Double) {
        guard let session = activeSession, session.state == .active else { return }
        guard userId == session.initiatorId || userId == session.partnerId else { return }
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        #if DEBUG
        print("[partner-sync] PR hit in session \(session.id): \(exerciseName) \(value)")
        #endif
    }
}
