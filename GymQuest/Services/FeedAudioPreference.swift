import Foundation
import Observation

/// Identifies a feed surface that owns its own session-scoped audio
/// preference. Friends and Discover each have an independent mute flag,
/// matching the user's expectation that muting on one feed does not
/// silence the other.
enum FeedAudioScope: String, Hashable {
    case friends
    case discover
}

/// Session-scoped mute preference for in-line feed audio (music previews
/// on PostCardV2). Mirrors Instagram Reels semantics: in-memory only,
/// resets to default (sound on) on cold launch. One flag per feed scope
/// so the Friends and Discover feeds maintain independent intent.
@Observable @MainActor
final class FeedAudioPreference {
    static let shared = FeedAudioPreference()

    private var friendsMuted: Bool = false
    private var discoverMuted: Bool = false

    private init() {}

    func isMuted(scope: FeedAudioScope) -> Bool {
        switch scope {
        case .friends: return friendsMuted
        case .discover: return discoverMuted
        }
    }

    func setMuted(_ muted: Bool, scope: FeedAudioScope) {
        switch scope {
        case .friends: friendsMuted = muted
        case .discover: discoverMuted = muted
        }
    }

    /// Flip the scope's flag and return the new value so callers can act
    /// on it (start playback when unmuting, stop when muting).
    @discardableResult
    func toggle(scope: FeedAudioScope) -> Bool {
        let next = !isMuted(scope: scope)
        setMuted(next, scope: scope)
        return next
    }
}
