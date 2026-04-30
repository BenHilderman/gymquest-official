// Messaging types — design v4.3 §6
// DM threads + messages, Squad chat threads + messages, comment reactions.

import Foundation
import SwiftData

enum DMMessageKind: String, Codable, CaseIterable {
    case text
    case voice
    case photo
    case video
    case workoutShare = "workout_share"
    case profileCard = "profile_card"
    case storyShare = "story_share"
    case crewShare = "crew_share"
    case partnerInvite = "partner_invite"
}

enum SquadMessageKind: String, Codable, CaseIterable {
    case text
    case voice
    case photo
    case video
    case workoutShare = "workout_share"
    case poll
    case systemEvent = "system_event"
    /// v4.3 Item H — chat-message reaction. Carries `parentMessageId`
    /// pointing at the message it reacts to and `reactionEmoji` holding
    /// the glyph. Renders as "[name] reacted [emoji] to chat" in the
    /// Slot 2 squad preview rotation.
    case reaction
}

enum SquadSystemEventKind: String, Codable {
    case workoutFinished = "workout_finished"
    case memberJoined = "member_joined"
    case memberLeft = "member_left"
    case quietNudge = "quiet_nudge"
}

@Model
final class DMThread {
    @Attribute(.unique) var id: UUID
    var participantA: UUID
    var participantB: UUID
    var lastMessageAt: Date
    var vanishModeA: Bool
    var vanishModeB: Bool
    var readReceiptsA: Bool
    var readReceiptsB: Bool
    var createdAt: Date

    init(participantA: UUID, participantB: UUID) {
        self.id = UUID()
        self.participantA = participantA
        self.participantB = participantB
        self.lastMessageAt = .init()
        self.vanishModeA = false
        self.vanishModeB = false
        self.readReceiptsA = true
        self.readReceiptsB = true
        self.createdAt = .init()
    }

    func participants() -> (UUID, UUID) { (participantA, participantB) }
}

@Model
final class DMMessage {
    @Attribute(.unique) var id: UUID
    var threadId: UUID
    var senderId: UUID
    var kindRaw: String
    var body: String?
    var mediaURL: String?
    var voiceDataRef: String?
    var photoDataRef: String?
    var workoutId: UUID?
    var sharedPostId: UUID?
    var partnerInviteWorkoutType: String?
    var expiresAt: Date?
    var editedAt: Date?
    var readAt: Date?
    var createdAt: Date

    init(
        threadId: UUID,
        senderId: UUID,
        kind: DMMessageKind,
        body: String? = nil,
        mediaURL: String? = nil,
        voiceDataRef: String? = nil,
        photoDataRef: String? = nil
    ) {
        self.id = UUID()
        self.threadId = threadId
        self.senderId = senderId
        self.kindRaw = kind.rawValue
        self.body = body
        self.mediaURL = mediaURL
        self.voiceDataRef = voiceDataRef
        self.photoDataRef = photoDataRef
        self.createdAt = .init()
    }

    var kind: DMMessageKind { DMMessageKind(rawValue: kindRaw) ?? .text }
}

@Model
final class SquadThread {
    @Attribute(.unique) var id: UUID
    var squadId: UUID
    var lastMessageAt: Date
    var quietNudgeEnabled: Bool
    var createdAt: Date

    init(squadId: UUID) {
        self.id = UUID()
        self.squadId = squadId
        self.lastMessageAt = .init()
        self.quietNudgeEnabled = false
        self.createdAt = .init()
    }
}

@Model
final class SquadMessage {
    @Attribute(.unique) var id: UUID
    var threadId: UUID
    var senderId: UUID?
    var kindRaw: String
    var body: String?
    var mediaURL: String?
    var voiceDataRef: String?
    var photoDataRef: String?
    var workoutId: UUID?
    var pollOptions: [String]?
    var pollVotes: [UUID: Int]?  // option index keyed by voter
    var systemEventKindRaw: String?
    /// v4.3 Item H — when `kind == .reaction`, the message this reaction
    /// is attached to. Nil for every other kind.
    var parentMessageId: UUID?
    /// v4.3 Item H — emoji glyph for reaction-kind messages. Nil otherwise.
    var reactionEmoji: String?
    var createdAt: Date

    init(
        threadId: UUID,
        senderId: UUID?,
        kind: SquadMessageKind,
        body: String? = nil,
        systemEventKind: SquadSystemEventKind? = nil,
        parentMessageId: UUID? = nil,
        reactionEmoji: String? = nil
    ) {
        self.id = UUID()
        self.threadId = threadId
        self.senderId = senderId
        self.kindRaw = kind.rawValue
        self.body = body
        self.systemEventKindRaw = systemEventKind?.rawValue
        self.parentMessageId = parentMessageId
        self.reactionEmoji = reactionEmoji
        self.createdAt = .init()
    }

    var kind: SquadMessageKind { SquadMessageKind(rawValue: kindRaw) ?? .text }
    var systemEventKind: SquadSystemEventKind? {
        systemEventKindRaw.flatMap(SquadSystemEventKind.init(rawValue:))
    }
}

/// Quick-comment chips for Comments + DMs (Gen Z native, design §3B + §6A).
enum QuickCommentChip: String, CaseIterable, Identifiable {
    case wsg = "wsg 🦍"
    case formCheck = "form check?"
    case sets = "sets?"
    case dropRoutine = "drop routine pls"
    case goat = "🐐"
    case seeYou = "see u tomorrow"
    case brutal = "ts brutal"
    case easyWork = "easy work"
    var id: String { rawValue }
}

/// DM pre-built openers for the "people you might DM" section (design §6A).
enum DMOpener: String, CaseIterable, Identifiable {
    case wsg = "wsg 🦍"
    case dropRoutine = "drop your routine pls"
    case liftingToday = "lifting today?"
    case seeYou = "see u tomorrow"
    var id: String { rawValue }
}

/// Smart caption suggestions for the post editor (Gen Z, design §7B).
enum SmartCaption: String, CaseIterable, Identifiable {
    case brutal = "ts brutal 🥲"
    case lockedIn = "locked in"
    case goat = "🐐 behavior"
    case easyWork = "easy work"
    case iPray = "i pray"
    case sendHelp = "send help"
    case neutral = ":/"
    case firstOfWeek = "first one of the week 🤝"
    var id: String { rawValue }
}
