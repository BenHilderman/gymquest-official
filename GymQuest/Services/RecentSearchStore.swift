import Foundation

/// A single row in the Discover search "Recent" list. Deliberately flat
/// so it persists to UserDefaults without SwiftData entanglement — each
/// entry captures enough to rehydrate a rich row without re-querying.
struct RecentSearchEntry: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case workout, exercise, person, club, query
    }

    var id: UUID
    let kind: Kind
    /// For workout/person/club: the model's id. For exercise: nil (identified
    /// by name). For query: nil. Lets tap-a-recent rehydrate the source.
    let subjectId: UUID?
    let label: String
    let subtitle: String?
    /// Optional thumbnail bytes for the row avatar. Post media thumbnail or
    /// profile photo — keeps UserDefaults size bounded by the 20-entry cap.
    let thumbnailData: Data?
    let addedAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        subjectId: UUID? = nil,
        label: String,
        subtitle: String? = nil,
        thumbnailData: Data? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.subjectId = subjectId
        self.label = label
        self.subtitle = subtitle
        self.thumbnailData = thumbnailData
        self.addedAt = addedAt
    }
}

/// UserDefaults-backed recent-search ring. 20-entry cap, newest-first.
/// Dedupes on (kind, subjectId || label) so tapping the same row twice
/// promotes rather than duplicates.
enum RecentSearchStore {
    private static let key = "discover_recent_searches_v1"
    private static let cap = 20

    static func load() -> [RecentSearchEntry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RecentSearchEntry].self, from: data)) ?? []
    }

    static func save(_ entries: [RecentSearchEntry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func add(_ entry: RecentSearchEntry) {
        var current = load()
        current.removeAll { existing in
            if let a = entry.subjectId, let b = existing.subjectId, entry.kind == existing.kind {
                return a == b
            }
            return existing.kind == entry.kind && existing.label.lowercased() == entry.label.lowercased()
        }
        current.insert(entry, at: 0)
        if current.count > cap { current = Array(current.prefix(cap)) }
        save(current)
    }

    static func remove(id: UUID) {
        var current = load()
        current.removeAll { $0.id == id }
        save(current)
    }

    static func clearAll() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
