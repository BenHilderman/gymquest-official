// Privacy & Trust types — design v4.3 §8A
// Ghost Mode 4 levels, post audience, granular reaction/DM/invite scopes.

import Foundation

enum GhostModeLevel: String, Codable, CaseIterable, Identifiable {
    case publicMode = "public"
    case friends
    case squad
    case ghost

    var id: String { rawValue }

    var label: String {
        switch self {
        case .publicMode: return "public"
        case .friends: return "friends"
        case .squad: return "squad"
        case .ghost: return "ghost"
        }
    }

    var subtitle: String {
        switch self {
        case .publicMode: return "anyone can see your live state"
        case .friends: return "people you follow back can see your live state"
        case .squad: return "only your squad can see your live state"
        case .ghost: return "no one can see your live state"
        }
    }

    /// Can the given viewer see live presence for an author with this Ghost Mode level?
    /// Matches the design's asymmetric trusted-friends rule.
    func allowsPresenceVisibility(forFollower isFollower: Bool, sameSquad: Bool) -> Bool {
        switch self {
        case .publicMode: return true
        case .friends: return isFollower
        case .squad: return sameSquad
        case .ghost: return false
        }
    }
}

// `PostAudience` lives in `Models.swift`. Extend it with the v4.3 surfaces
// (Identifiable + the lowercase label / systemIcon helpers used by the new
// pickers). Close-friends scoping is enforced via `close_friends` table RLS,
// not via this client-side enum yet.
extension PostAudience: Identifiable {
    public var id: String { rawValue }

    /// Lowercase Gen-Z label used in the v4.3 pickers / chips.
    var v43Label: String {
        switch self {
        case .friends: return "friends"
        case .squad: return "squad"
        case .public: return "public"
        }
    }

    /// SF Symbol matching the existing `iconSF` mapping — re-exported so v4.3
    /// call sites can use a single name across the app.
    var systemIcon: String { iconSF }
}

enum ReactionKind: String, Codable, CaseIterable, Identifiable {
    case emoji
    case voice
    case photo
    var id: String { rawValue }
}

/// Granular permission scopes for who can react / DM / invite to Partner Mode.
/// Maps to the Privacy & Trust panel toggles.
enum SocialPermissionScope: String, Codable, CaseIterable, Identifiable {
    case everyone
    case followers
    case mutuals
    case friends
    case closeFriends = "close_friends"
    case squad
    case noOne = "no_one"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everyone: return "everyone"
        case .followers: return "followers"
        case .mutuals: return "mutuals only"
        case .friends: return "friends"
        case .closeFriends: return "close friends"
        case .squad: return "squad"
        case .noOne: return "no one"
        }
    }
}

/// Notification categories matching the v4.3 design §8B list.
enum NotificationCategory: String, Codable, CaseIterable, Identifiable {
    case friendStarts = "friend_starts"
    case friendFinishes = "friend_finishes"
    case reactionEmoji = "reaction_emoji"
    case reactionVoice = "reaction_voice"
    case reactionPhoto = "reaction_photo"
    case comment
    case dm
    case storyView = "story_view"
    case tagMention = "tag_mention"
    case crewEvent = "crew_event"
    case squadChat = "squad_chat"
    case squadReminder = "squad_reminder"
    case partnerInvite = "partner_invite"
    case streakNudge = "streak_nudge"
    case aiCoachPrompt = "ai_coach_prompt"
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .friendStarts: return "friend starts workout"
        case .friendFinishes: return "friend finishes workout"
        case .reactionEmoji: return "emoji reactions"
        case .reactionVoice: return "voice reactions"
        case .reactionPhoto: return "photo reactions"
        case .comment: return "comments"
        case .dm: return "DMs"
        case .storyView: return "story views"
        case .tagMention: return "tags + mentions"
        case .crewEvent: return "crew events"
        case .squadChat: return "squad chat"
        case .squadReminder: return "squad reminders"
        case .partnerInvite: return "partner mode invites"
        case .streakNudge: return "streak nudges"
        case .aiCoachPrompt: return "AI coach prompts"
        case .system: return "system"
        }
    }
}

/// User-visible bundle of Privacy & Trust settings. Backed by Supabase tables.
/// Not Codable — the dictionary of `NotificationCategory: Bool` doesn't synthesize
/// cleanly with non-String dictionary keys. The wire format is per-row in
/// `notification_preferences` / `ghost_mode` / etc.
struct PrivacyTrustSettings {
    var ghostModeLevel: GhostModeLevel = .friends
    var defaultPostAudience: PostAudience = .friends
    var canReactEmoji: SocialPermissionScope = .followers
    var canReactVoice: SocialPermissionScope = .friends
    var canReactPhoto: SocialPermissionScope = .friends
    var canDM: SocialPermissionScope = .mutuals
    var canInviteToPartner: SocialPermissionScope = .mutuals
    var enableComparisonStats: Bool = true
    var allowAutoReact: Bool = false
    var notifications: [NotificationCategory: Bool] = Dictionary(
        uniqueKeysWithValues: NotificationCategory.allCases.map { ($0, true) }
    )
}
