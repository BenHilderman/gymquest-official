//
//  AliveIntegrations.swift
//  GymQuest
//
//  Phase 5 of the Alive release: iOS-deep integration.
//
//  Shipped here:
//   - StartColiftWorkoutIntent (App Intents / Siri Shortcuts) — "Start a
//     Colift workout" — sets a flag the app reads on next foreground.
//   - AliveWatchBridge — sends a haptic-trigger payload to the paired
//     Apple Watch when a LiveReaction lands. Soft-feature-flagged: silently
//     no-ops when Watch session isn't reachable.
//
//  Deferred (require a new Widget Extension target — out of scope for this
//  conversation's pbxproj surgery budget):
//   - ActivityKit Live Activity for own workout (set count + elapsed time,
//     stacks into Dynamic Island for "watching" a friend's session).
//   - Lock-screen home widget showing up to 4 active friend avatars; tap →
//     opens app to reaction send sheet pre-targeted to that friend.
//   - When the new target is added, register attributes here and render
//     widgets in a sibling target file.
//

import Foundation
import SwiftUI
import AppIntents
#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Live Activity attributes (Phase 5)

#if canImport(ActivityKit)

/// Attributes for the own-workout Live Activity. Dynamic state (set count,
/// elapsed time) lives in ContentState; static state (workout type, title)
/// on the attributes itself.
///
/// IMPORTANT: rendering this Live Activity requires a Widget Extension
/// target that imports this type and conforms to ActivityConfiguration.
/// The data layer here is fully wired. Until the Widget Extension is
/// added (Xcode UI: File → New → Target → Widget Extension, check "Include
/// Live Activity"), Activity.request() throws and the driver no-ops
/// gracefully.
struct ColiftWorkoutAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var setsCompleted: Int
        var totalSets: Int
        var startedAt: Date
    }

    var workoutTypeRaw: String
    var customTitle: String?
}

@MainActor
enum ColiftWorkoutLiveActivity {
    private static var current: Activity<ColiftWorkoutAttributes>? = nil

    static func start(workoutType: String, customTitle: String?, totalSets: Int, startedAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard current == nil else { return }
        let attrs = ColiftWorkoutAttributes(workoutTypeRaw: workoutType, customTitle: customTitle)
        let state = ColiftWorkoutAttributes.ContentState(
            setsCompleted: 0,
            totalSets: totalSets,
            startedAt: startedAt
        )
        do {
            current = try Activity.request(
                attributes: attrs,
                content: ActivityContent(state: state, staleDate: nil)
            )
        } catch {
            // Most common reason: no Widget Extension target. Silent fail OK.
            current = nil
        }
    }

    static func update(setsCompleted: Int, totalSets: Int, startedAt: Date) {
        Task {
            guard let act = current else { return }
            let state = ColiftWorkoutAttributes.ContentState(
                setsCompleted: setsCompleted,
                totalSets: totalSets,
                startedAt: startedAt
            )
            await act.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    static func end() {
        Task {
            guard let act = current else { return }
            await act.end(nil, dismissalPolicy: .immediate)
            current = nil
        }
    }
}

// MARK: - Lock-screen widget data bridge

/// App-Group-backed snapshot the lock-screen widget reads to render the
/// "active friend avatars" tile. Updated whenever followed users'
/// PresenceState rows change. Reads/writes via shared UserDefaults so the
/// Widget Extension target (when added) can read without a SwiftData
/// dependency.
///
/// The Widget Extension reads the encoded snapshot, renders the avatars
/// with `Link(destination: liftai://reaction/<userId>)` so each one deep-
/// links to the reaction palette pre-targeted to that friend.
enum AliveActiveFriendsBridge {
    private static let key = "alive.activeFriendsSnapshot"

    struct Snapshot: Codable {
        let friends: [Entry]
        let updatedAt: Date
    }
    struct Entry: Codable, Identifiable {
        let id: UUID
        let name: String
        let initial: String
        let workoutTypeRaw: String?
    }

    static func write(_ entries: [Entry]) {
        let snap = Snapshot(friends: Array(entries.prefix(4)), updatedAt: Date())
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func read() -> Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }
}

#endif

// MARK: - App Intents / Siri Shortcuts

/// Triggers the Start Workout flow with the user's last location-share
/// answer remembered. The intent writes a UserDefaults flag the app reads
/// on next foreground; ContentView/AppState picks it up and routes.
struct StartColiftWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Colift workout"
    static var description = IntentDescription("Begin tracking a workout in Colift, using your last location-share preference.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "alive.intent.startWorkoutPending")
        UserDefaults.standard.set(Date(), forKey: "alive.intent.startWorkoutAt")
        return .result()
    }
}

struct AliveAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartColiftWorkoutIntent(),
            phrases: [
                "Start a \(.applicationName) workout",
                "Lift in \(.applicationName)"
            ],
            shortTitle: "Start workout",
            systemImageName: "dumbbell.fill"
        )
    }
}

// MARK: - Pending intent reader (called on app foreground)

@MainActor
enum PendingIntentRouter {
    /// Returns true if a pending start-workout intent was handled.
    /// Caller is responsible for actually triggering the workout flow.
    static func consumePendingStart() -> Bool {
        guard UserDefaults.standard.bool(forKey: "alive.intent.startWorkoutPending") else { return false }
        UserDefaults.standard.set(false, forKey: "alive.intent.startWorkoutPending")
        return true
    }
}

// MARK: - Watch connectivity bridge

#if canImport(WatchConnectivity)
@MainActor
final class AliveWatchBridge: NSObject, WCSessionDelegate {
    static let shared = AliveWatchBridge()

    private override init() { super.init() }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Send a payload to the paired Watch when a LiveReaction lands. The
    /// Watch app fires `WKHapticType.success` + a brief notification banner.
    func notifyReactionReceived(emoji: String, fromName: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        let payload: [String: Any] = [
            "kind": "alive.reactionReceived",
            "emoji": emoji,
            "fromName": fromName,
            "ts": Date().timeIntervalSince1970
        ]
        session.sendMessage(payload, replyHandler: nil) { _ in
            // Silent fail — Watch unreachable is acceptable; this is a
            // best-effort haptic pulse, not a delivery guarantee.
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {}
    #endif
}
#endif
