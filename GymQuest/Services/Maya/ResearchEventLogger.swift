// ResearchEventLogger — lightweight event log for the Maya MVP user
// test (target: 100 participants). Each event captures the timestamp,
// session id, optional participant id, event name, and a string-keyed
// metadata bag.
//
// Storage strategy:
//   - In-memory buffer always.
//   - DEBUG builds: also prints to console with a `[research]` prefix
//     and persists the buffer to a JSON file under the app's caches
//     directory so manual tester sessions can be retrieved later.
//   - Release builds: in-memory only. No personal data collected.
//
// Participant ID is opt-in for the researcher running the test — set
// via UserDefaults key `mayaParticipantId` (debug only).

import Foundation

@MainActor
final class ResearchEventLogger {
    static let shared = ResearchEventLogger()

    /// One sessionId per cold-app-launch — kept stable through tab/page
    /// transitions until the process restarts.
    let sessionId: UUID

    /// Captured participant ID — set via UserDefaults for the
    /// researcher running the test. Nil in normal user installs.
    var participantId: String? {
        get { UserDefaults.standard.string(forKey: Self.participantIdKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: Self.participantIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.participantIdKey)
            }
        }
    }

    private(set) var events: [ResearchEvent] = []

    private static let participantIdKey = "mayaParticipantId"

    private init() {
        self.sessionId = UUID()
    }

    // MARK: - Logging API

    /// Log a research event. Metadata is keyed strings only — strict
    /// to keep events scannable + redactable. Caller passes the event
    /// name as a `ResearchEventName` so typos can't reach the log.
    func log(_ name: ResearchEventName, metadata: [String: String] = [:]) {
        let event = ResearchEvent(
            sessionId: sessionId,
            participantId: participantId,
            eventName: name.rawValue,
            metadata: metadata
        )
        events.append(event)

        #if DEBUG
        let pid = participantId.map { "p=\($0) " } ?? ""
        let meta = metadata.isEmpty ? "" : " · \(metadata.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ","))"
        print("[research] \(pid)\(name.rawValue)\(meta)")
        persistDebugBuffer()
        #endif
    }

    /// Convenience for session-keyed events that should always include
    /// the replay context.
    func log(
        _ name: ResearchEventName,
        session: MayaWorkoutSession,
        extra: [String: String] = [:]
    ) {
        var metadata = extra
        metadata["replayId"] = session.replay.id.uuidString
        metadata["replayTitle"] = session.replay.title
        metadata["currentExerciseIndex"] = "\(session.currentExerciseIndex)"
        metadata["currentSetIndex"] = "\(session.currentSetIndex)"
        log(name, metadata: metadata)
    }

    /// Returns the buffer encoded as pretty-printed JSON — useful for
    /// the researcher to copy out of a manual debug session.
    func exportJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(events) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Wipes the buffer (debug-only convenience for resetting between
    /// test sessions without relaunching).
    func reset() {
        events.removeAll()
        #if DEBUG
        persistDebugBuffer()
        #endif
    }

    // MARK: - Debug persistence

    #if DEBUG
    /// Writes the current buffer to `~/Library/Caches/research-events.json`
    /// inside the app sandbox. Best-effort — fails silently.
    private func persistDebugBuffer() {
        guard let json = exportJSON(),
              let cachesDir = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
              ).first else { return }
        let url = cachesDir.appendingPathComponent("research-events.json")
        try? json.data(using: .utf8)?.write(to: url, options: .atomic)
    }
    #endif
}

// MARK: - Event name vocabulary

/// The hard-coded set of event names the MVP emits. Adding a new event
/// requires adding a case here — keeps the research schema typo-proof.
enum ResearchEventName: String {
    case app_opened
    case cold_start_viewed
    case replay_chip_selected
    case start_replay_tapped
    case active_replay_viewed
    case set_completed
    case rest_started
    case rest_completed
    case rest_extended
    case next_set_started
    case exercise_completed
    case workout_completed
    case shared_win_viewed
    case save_win_tapped
    case not_now_tapped
    case saved_screen_viewed
    case run_it_back_tapped
    case try_another_replay_tapped
    case session_abandoned
    case skip_adjust_tapped
    case notification_default_off_verified
}
