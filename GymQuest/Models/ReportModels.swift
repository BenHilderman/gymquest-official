// Report-system enums + UserBlock model — content-safety phase 3.
//
// Note: the `ContentReport` SwiftData @Model already lives in Models.swift
// and uses string-based `contentType` + `reason` fields. The enums below
// are the source of truth that ContentReportService maps onto/off the
// existing model.

import Foundation
import SwiftData

enum ContentReportTargetKind: String, Codable, CaseIterable {
    case post
    case comment
    case dmMessage = "dm_message"
    case squadMessage = "squad_message"
    case story
    case user
}

enum ContentReportReason: String, Codable, CaseIterable, Identifiable {
    case spam
    case abuse           // harassment, threats
    case nsfw            // explicit / not safe
    case offTopic = "off_topic"
    case impersonation
    case selfHarm = "self_harm"
    case other

    var id: String { rawValue }

    var displayLabel: String {
        switch self {
        case .spam: return "spam"
        case .abuse: return "harassment / abuse"
        case .nsfw: return "not safe for everyone"
        case .offTopic: return "off-topic"
        case .impersonation: return "impersonation"
        case .selfHarm: return "self-harm"
        case .other: return "something else"
        }
    }
}

/// Block edge — directed: `userId` blocks `blockedUserId`. Each side
/// of a mutual block writes its own row. Block hides target's content
/// from `userId`'s feed and prevents new DMs / mentions / tags.
@Model
final class UserBlock {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var blockedUserId: UUID
    var createdAt: Date

    init(userId: UUID, blockedUserId: UUID) {
        self.id = UUID()
        self.userId = userId
        self.blockedUserId = blockedUserId
        self.createdAt = .init()
    }
}
