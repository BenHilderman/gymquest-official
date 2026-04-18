import Foundation

/// Deep-link plumbing for "share a club invite" flows.
///
/// URL shape: `liftai://club-invite/<clubId>?code=<inviteCode>`
///   - `clubId` — required; Club.id as UUID string
///   - `code`   — optional; for .squad kind Clubs, unlocks auto-join when present
///                and matches `Club.inviteCode`. For .community kind Clubs the
///                code is ignored and join follows the Club's `joinType`.
///
/// Callers:
///   - Share-sheet export: `ClubInviteService.inviteURL(for: club)`
///   - `onOpenURL` hook in GymQuestApp: `ClubInviteService.parse(url:)`
enum ClubInviteService {

    /// Well-known URL scheme registered in Info.plist.
    static let scheme = "liftai"
    static let host = "club-invite"

    struct Invite: Equatable {
        let clubId: UUID
        let code: String?
    }

    /// Construct a shareable invite URL for a Club.
    static func inviteURL(for club: Club) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/" + club.id.uuidString
        if let code = club.inviteCode, !code.isEmpty, club.kind == .squad {
            components.queryItems = [URLQueryItem(name: "code", value: code)]
        }
        return components.url
    }

    /// Parse an incoming `liftai://club-invite/...` URL into an `Invite`.
    /// Returns nil when the URL is unrelated or malformed.
    static func parse(url: URL) -> Invite? {
        guard url.scheme == scheme, url.host == host else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // path = "/<uuid>" → strip leading slash
        let idString = url.pathComponents.first(where: { $0 != "/" }) ?? ""
        guard let clubId = UUID(uuidString: idString) else { return nil }
        let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
        return Invite(clubId: clubId, code: code?.isEmpty == false ? code : nil)
    }
}
