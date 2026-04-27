//
//  AliveLocation.swift
//  GymQuest
//
//  Phase 3 of the Alive release: location privacy.
//  - SavedGyms management lives here (lightweight, capped at 3).
//  - AliveLocationService requests `whenInUse` only and emits geofence
//    "arrived at <gym>" events.
//  - LocationOptInDialog is the per-session question shown at workout start:
//    "Show friends you're at <Gym>?" → Yes / Just-active / Ghost.
//  - AtMyGymBanner surfaces when the user is geofenced into a gym AND a
//    Friend's PresenceState.gymId matches.
//  - Stealth co-presence: even if the user has gymId = nil, the banner
//    can surface FROM the user's POV, but never appears on the friend's
//    side. Privacy goes one direction.
//

import SwiftUI
import SwiftData
import CoreLocation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Per-friend asymmetric trust list

/// "Who can see my gym name when I'm there?" — a UserDefaults-backed set
/// of friend UUIDs the user has explicitly opted in. Asymmetric: I add
/// Marcus to this list ⇒ Marcus may see "Olivia is at the ARC". It does
/// NOT mean I see Marcus's gym — that requires Marcus to add me to his
/// own trust list.
///
/// This replaces the per-session "Yes / Just-active / Ghost" dialog at
/// workout start — once-per-friend decisions accumulate into a stable
/// trust shape, no recurring interruption.
enum LocationTrustedFriendsStore {
    private static let key = "alive.locationTrustedFriends"

    static func load() -> Set<UUID> {
        let strings = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }

    static func contains(_ id: UUID) -> Bool { load().contains(id) }

    static func add(_ id: UUID) {
        var current = load()
        current.insert(id)
        save(current)
    }

    static func remove(_ id: UUID) {
        var current = load()
        current.remove(id)
        save(current)
    }

    static func toggle(_ id: UUID) {
        if contains(id) { remove(id) } else { add(id) }
    }

    private static func save(_ ids: Set<UUID>) {
        UserDefaults.standard.set(ids.map { $0.uuidString }, forKey: key)
    }
}

// MARK: - Location service

@MainActor
final class AliveLocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = AliveLocationService()

    private let manager = CLLocationManager()
    @Published private(set) var lastLocation: CLLocation? = nil
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Most recent gym the user is geofenced inside, if any. Updated on
    /// every location update. Strangers never see this — it stays in-app.
    @Published private(set) var currentGym: SavedGym? = nil

    /// Snapshot of saved gyms used to compute geofence membership. Refresh
    /// from SwiftData on call.
    private var savedGyms: [SavedGym] = []

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
    }

    func refresh(savedGyms: [SavedGym]) {
        self.savedGyms = savedGyms
        recomputeGym()
    }

    func requestPermission() {
        guard LocationOptInStore.enabled else { return }
        manager.requestWhenInUseAuthorization()
    }

    func startMonitoring() {
        guard LocationOptInStore.enabled else { return }
        manager.startUpdatingLocation()
    }

    func stopMonitoring() {
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.lastLocation = loc
            self.recomputeGym()
        }
    }

    private func recomputeGym() {
        guard let loc = lastLocation else { currentGym = nil; return }
        let match = savedGyms.first { gym in
            let distance = loc.distance(from: CLLocation(latitude: gym.latitude, longitude: gym.longitude))
            return distance <= gym.radiusMeters
        }
        if currentGym?.id != match?.id {
            let prior = currentGym
            currentGym = match
            // Fire arrival notification only on transition nil → matched.
            if prior == nil, let arrived = match {
                GeofenceArrivalNotifier.fire(for: arrived)
            }
        }
    }
}

// MARK: - Geofence arrival notification

@MainActor
enum GeofenceArrivalNotifier {
    /// Asked-for-but-not-required permission. Fail closed — if the user
    /// declines, the silent rejection is fine; we just won't ping them.
    static func ensurePermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Posts a foreground-friendly notification on entry into a SavedGym.
    /// Identifier uses the gym id so duplicates are de-duped automatically.
    /// Action buttons are not included here — the user taps the notif and
    /// lands in the app, where the per-session dialog at workout start
    /// handles the rest.
    static func fire(for gym: SavedGym) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Arrived at \(gym.name)"
        content.body = "Start workout?"
        content.sound = .default

        // Set presence to .arriving (gold ring) so peers see the
        // about-to-train signal until the user actually taps Start.
        AliveLocationStateWriter.markArriving(userId: ownUserIdSnapshot, gymId: gym.id, gymName: gym.name)

        let req = UNNotificationRequest(
            identifier: "alive.arrived.\(gym.id.uuidString)",
            content: content,
            trigger: nil
        )
        center.add(req) { _ in }
    }

    /// User-id read from a singleton bridge that the app must populate
    /// before the location service starts. Defaults to a sentinel UUID
    /// when unset — all writes against it are no-ops.
    nonisolated(unsafe) static var ownUserIdSnapshot: UUID = UUID()
}

// MARK: - Per-session opt-in dialog

enum LocationShareChoice: String {
    case yes        // share gymId + gymName with friends
    case justActive // status = .training, gymId nil
    case ghost      // status = .ghost, no presence at all
}

/// Modal sheet shown when the user taps Start Workout. Choice flips
/// `PresenceState` fields per the spec.
struct LocationShareDialog: View {
    let gymName: String?
    let onSelect: (LocationShareChoice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Who can see you train?")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(GQColors.textPrimary)
                .padding(.top, 16)

            if let name = gymName, !name.isEmpty {
                Text("You're at \(name). Strangers never see this — only friends you choose.")
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Friends will only see what you pick. Strangers never see where you train.")
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                choiceButton(.yes,
                             title: gymName.map { "Show friends I'm at \($0)" } ?? "Share my gym with friends",
                             subtitle: "Friends see name + active",
                             icon: "location.fill",
                             primary: true)
                choiceButton(.justActive,
                             title: "Just show I'm active",
                             subtitle: "Friends see I'm training, no location",
                             icon: "figure.run",
                             primary: false)
                choiceButton(.ghost,
                             title: "Ghost this session",
                             subtitle: "Nobody sees this workout at all",
                             icon: "eye.slash",
                             primary: false)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 18)
        .background(GQColors.background)
    }

    @ViewBuilder
    private func choiceButton(_ choice: LocationShareChoice, title: String, subtitle: String, icon: String, primary: Bool) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            onSelect(choice)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(primary ? GQColors.deepBlue.opacity(0.12) : GQColors.surfaceBase)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(primary ? AnyShapeStyle(GQGradients.primary) : AnyShapeStyle(GQColors.textSecondary))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                    Text(subtitle)
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
}

// MARK: - At-my-gym banner

/// Surfaces when the user is geofenced into a gym AND a Friend's
/// PresenceState.gymId matches that gym (privacy: friend must have
/// opted in). Tap-to-broadcast button sends a "joining" reaction.
struct AtMyGymBanner: View {
    let friendName: String
    let friendUserId: UUID
    let gymName: String
    let fromUserId: UUID
    @Environment(\.modelContext) private var modelContext

    @State private var didNotify: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AlivePresence.gold.opacity(0.18))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "figure.walk")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AlivePresence.gold)
                )
                .presenceRing(friendUserId, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(friendName) is at \(gymName)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                Text("Walk over?")
                    .font(.system(size: 12))
                    .foregroundColor(GQColors.textSecondary)
            }
            Spacer()
            Button {
                tellFriendIArrived()
            } label: {
                Text(didNotify ? "Sent ✓" : "Tell \(firstName(friendName))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(didNotify ? AnyShapeStyle(AlivePresence.green) : AnyShapeStyle(GQGradients.primary)))
            }
            .buttonStyle(.plain)
            .disabled(didNotify)
        }
        .padding(14)
        .homeSocialCard(cornerRadius: 14)
    }

    private func firstName(_ s: String) -> String {
        s.split(separator: " ").first.map(String.init) ?? s
    }

    private func tellFriendIArrived() {
        let r = LiveReaction(
            fromUserId: fromUserId,
            toUserId: friendUserId,
            sessionStartedAt: Date(),
            kind: "joining",
            quickReplyText: "I'm here too — \(gymName)"
        )
        modelContext.insert(r)
        try? modelContext.save()
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            didNotify = true
        }
    }
}

// MARK: - Presence-state writer for per-session location decisions

/// Helpers that mutate a user's existing `UserPresenceState` to encode the
/// per-session privacy choice. Called from the workout-start dialog.
@MainActor
enum AliveLocationStateWriter {
    static func writeGym(
        userId: UUID,
        gymId: UUID?,
        gymName: String?,
        sessionTags: [String],
        in modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<UserPresenceState>(
            predicate: #Predicate { $0.userId == userId }
        )
        guard let state = try? modelContext.fetch(descriptor).first else { return }
        state.gymId = gymId
        state.gymName = gymName
        state.sessionTags = sessionTags
        state.updatedAt = Date()
        try? modelContext.save()
    }

    /// Sets status = .arriving (gold ring) on geofence entry, before the
    /// user has actually started a workout. Cleared as soon as setTraining
    /// fires (or setIdle on cancel).
    @MainActor
    static func markArriving(userId: UUID, gymId: UUID?, gymName: String?) {
        guard let context = AliveLocationModelContextBridge.shared.modelContext else { return }
        let descriptor = FetchDescriptor<UserPresenceState>(
            predicate: #Predicate { $0.userId == userId }
        )
        if let state = try? context.fetch(descriptor).first {
            state.status = .arriving
            state.gymId = gymId
            state.gymName = gymName
            state.startedAt = nil
            state.updatedAt = Date()
        } else {
            let fresh = UserPresenceState(
                userId: userId,
                status: .arriving,
                workoutType: nil,
                startedAt: nil,
                gymId: gymId,
                gymName: gymName
            )
            context.insert(fresh)
        }
        try? context.save()
    }

    static func writeGhost(userId: UUID, in modelContext: ModelContext) {
        let descriptor = FetchDescriptor<UserPresenceState>(
            predicate: #Predicate { $0.userId == userId }
        )
        if let state = try? modelContext.fetch(descriptor).first {
            state.status = .ghost
            state.gymId = nil
            state.gymName = nil
            state.sessionTags = ["ghost"]
            state.startedAt = Date()
            state.updatedAt = Date()
        } else {
            let fresh = UserPresenceState(
                userId: userId,
                status: .ghost,
                workoutType: nil,
                startedAt: Date(),
                gymId: nil,
                gymName: nil,
                sessionTags: ["ghost"]
            )
            modelContext.insert(fresh)
        }
        try? modelContext.save()
    }
}

// MARK: - ModelContext bridge for non-View writers

/// Lets non-View utilities (notification handler, scheduled scans) write
/// SwiftData rows. TodayView populates this on appear so writes from a
/// background CoreLocation callback have a route into the store.
@MainActor
final class AliveLocationModelContextBridge {
    static let shared = AliveLocationModelContextBridge()
    weak var modelContext: ModelContext?
    private init() {}
}

// MARK: - Demo seed (one SavedGym per user) so AtMyGymBanner has data to resolve

@MainActor
enum SavedGymSeeder {
    /// Inserts a single demo SavedGym ("The ARC") for the current user the
    /// first time the user opens Today. Idempotent.
    static func seedIfNeeded(userId: UUID, in modelContext: ModelContext) {
        let theArcId = UUID(uuidString: "ABCDEF12-0000-0000-0000-000000000001")!
        let descriptor = FetchDescriptor<SavedGym>(
            predicate: #Predicate { $0.id == theArcId }
        )
        if let existing = try? modelContext.fetch(descriptor), existing.contains(where: { $0.userId == userId }) {
            return
        }
        let gym = SavedGym(
            id: theArcId,
            userId: userId,
            name: "The ARC",
            latitude: 44.225,
            longitude: -76.490,
            radiusMeters: 80,
            nickname: nil
        )
        modelContext.insert(gym)
        try? modelContext.save()
    }
}

// MARK: - Resolver: which AtMyGym banners to show

/// Looks up friends present at the same gym the user is geofenced into.
/// Returns nil when there's no current gym match. One-direction privacy:
/// caller must check `LocationOptInStore.enabled` for the FRIEND side
/// before flipping any reverse-direction state.
@MainActor
enum AtMyGymResolver {
    struct Match: Identifiable, Equatable {
        let id: UUID
        let userId: UUID
        let userName: String
        let gymName: String
    }

    static func matches(
        currentGymId: UUID?,
        followedIds: Set<UUID>,
        states: [UserPresenceState],
        nameLookup: (UUID) -> String
    ) -> [Match] {
        guard let gymId = currentGymId else { return [] }
        let now = Date()
        return states.compactMap { state in
            guard followedIds.contains(state.userId) else { return nil }
            guard state.gymId == gymId, let gymName = state.gymName else { return nil }
            switch state.status {
            case .training, .resting, .arriving: break
            default: return nil
            }
            if let started = state.startedAt, now.timeIntervalSince(started) > 3 * 3600 {
                return nil
            }
            return Match(id: state.userId, userId: state.userId, userName: nameLookup(state.userId), gymName: gymName)
        }
    }
}
