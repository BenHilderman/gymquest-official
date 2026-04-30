// Story types — design v4.3 §3C
// Composer modes, viewer state, sticker pack, audience.

import Foundation
import SwiftData

enum StoryKind: String, Codable, CaseIterable, Identifiable {
    case photo
    case video
    case text
    case workoutShare = "workout_share"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .photo: return "photo"
        case .video: return "video"
        case .text: return "text"
        case .workoutShare: return "workout"
        }
    }
}

enum StoryStickerKind: String, Codable, CaseIterable, Identifiable {
    case workoutType = "workout_type"
    case pr
    case gymName = "gym_name"
    case song
    case mood
    case countdown
    case poll
    var id: String { rawValue }
}

struct StorySticker: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var kind: StoryStickerKind
    var payload: [String: String] = [:]
    var x: Double = 0.5
    var y: Double = 0.5
    var rotation: Double = 0
    var scale: Double = 1.0
}

@Model
final class Story {
    @Attribute(.unique) var id: UUID
    var authorId: UUID
    var kindRaw: String
    var mediaURL: String?
    var textBody: String?
    var workoutId: UUID?
    var stickerPayloadRaw: Data?  // JSON-encoded [StorySticker]
    var audienceRaw: String
    var audienceSquadId: UUID?
    var songTitle: String?
    var artistName: String?
    var postedAt: Date
    var expiresAt: Date
    var viewCount: Int
    var isDeleted: Bool

    init(
        authorId: UUID,
        kind: StoryKind,
        mediaURL: String? = nil,
        textBody: String? = nil,
        workoutId: UUID? = nil,
        stickers: [StorySticker] = [],
        audience: PostAudience = .friends,
        audienceSquadId: UUID? = nil
    ) {
        self.id = UUID()
        self.authorId = authorId
        self.kindRaw = kind.rawValue
        self.mediaURL = mediaURL
        self.textBody = textBody
        self.workoutId = workoutId
        self.stickerPayloadRaw = try? JSONEncoder().encode(stickers)
        self.audienceRaw = audience.rawValue
        self.audienceSquadId = audienceSquadId
        self.postedAt = .init()
        self.expiresAt = Date().addingTimeInterval(24 * 60 * 60)
        self.viewCount = 0
        self.isDeleted = false
    }

    var kind: StoryKind { StoryKind(rawValue: kindRaw) ?? .photo }
    var audience: PostAudience { PostAudience(rawValue: audienceRaw) ?? .friends }
    var stickers: [StorySticker] {
        guard let data = stickerPayloadRaw else { return [] }
        return (try? JSONDecoder().decode([StorySticker].self, from: data)) ?? []
    }

    var isActive: Bool { !isDeleted && expiresAt > .init() }
}

@Model
final class StoryHighlightSlot {
    @Attribute(.unique) var compositeKey: String  // userId + slotIndex
    var userId: UUID
    var slotIndex: Int
    var storyId: UUID
    var title: String?
    var pinnedAt: Date
    /// v4.3 §5A — when the owner last viewed this highlight themselves.
    /// Drives the "fresh" dot: shown on highlights not viewed in 30+ days
    /// so the owner re-discovers their own pinned moments. Owner-only.
    var ownerLastViewedAt: Date?

    init(userId: UUID, slotIndex: Int, storyId: UUID, title: String? = nil) {
        self.compositeKey = "\(userId.uuidString)-\(slotIndex)"
        self.userId = userId
        self.slotIndex = slotIndex
        self.storyId = storyId
        self.title = title
        self.pinnedAt = .init()
    }

    var ownerHasNotViewedRecently: Bool {
        guard let last = ownerLastViewedAt else { return true }
        return Date().timeIntervalSince(last) > 30 * 86_400
    }
}
