// MayaModels — data layer for the locked CoLift Maya MVP validation
// build. Self-contained: pure structs for replay content (read from a
// static library), SwiftData @Models for state that needs to survive
// across launches (SavedWin, RunItBackState).
//
// Naming uses the `Maya` prefix on session/exercise types to avoid
// collision with the existing legacy `Workout` / `Exercise` SwiftData
// classes. The Maya MVP intentionally does NOT touch those — it lives
// alongside the existing app, gated behind `validationMVPEnabled`.
//
// Per the locked product spec, Maya is a guide character, not a user:
// no follow / message / thank / reactions / inbound or outbound social.

import Foundation
import SwiftData

// MARK: - Replay (content, in-memory)

/// One Maya replay — a guided lift session. Pure struct because the
/// content is shipped in-app via `MayaReplayLibrary`, never
/// user-authored or persisted.
struct Replay: Identifiable, Hashable {
    let id: UUID
    let title: String
    let durationMinutes: Int
    /// All Maya replays are no-invite-needed by definition; field is
    /// kept explicit because the Cold Start chip text reads off it.
    let noInviteNeeded: Bool
    /// Display tag chip shown on the Cold Start card ("good first lift").
    let tag: String
    /// Which selection chip routes here.
    let chipType: ReplayChipType
    /// Always "Maya" for v1; field kept so the rendering layer never
    /// hard-codes the persona name.
    let guideName: String
    /// "guided replay" — small subline under the Maya avatar.
    let guideSubtitle: String
    /// "maya's form cue" — label used on the Cold Start preview card.
    let cuePreviewLabel: String
    /// Body text of the cue preview — pulled forward to the first
    /// screen so the user can see proof-of-value before tapping Start.
    let cuePreviewText: String
    let exercises: [MayaExercise]

    init(
        id: UUID = UUID(),
        title: String,
        durationMinutes: Int,
        noInviteNeeded: Bool = true,
        tag: String,
        chipType: ReplayChipType,
        guideName: String = "Maya",
        guideSubtitle: String = "guided replay",
        cuePreviewLabel: String = "maya's form cue",
        cuePreviewText: String,
        exercises: [MayaExercise]
    ) {
        self.id = id
        self.title = title
        self.durationMinutes = durationMinutes
        self.noInviteNeeded = noInviteNeeded
        self.tag = tag
        self.chipType = chipType
        self.guideName = guideName
        self.guideSubtitle = guideSubtitle
        self.cuePreviewLabel = cuePreviewLabel
        self.cuePreviewText = cuePreviewText
        self.exercises = exercises
    }

    var totalExercises: Int { exercises.count }
}

// MARK: - ReplayChipType

/// The selection chips on Cold Start. Each maps to exactly one Replay
/// in `MayaReplayLibrary.replay(for:)`. Order in `allCases` is the
/// order they render.
enum ReplayChipType: String, CaseIterable, Identifiable, Codable {
    case goodFirstLift
    case returningAfterBreak
    case upperBody
    case lowerBody
    case quickLift

    var id: String { rawValue }

    /// User-facing chip label.
    var label: String {
        switch self {
        case .goodFirstLift:       return "good first lift"
        case .returningAfterBreak: return "returning after a break"
        case .upperBody:           return "upper body"
        case .lowerBody:           return "lower body"
        case .quickLift:           return "quick lift"
        }
    }
}

// MARK: - MayaExercise (content)

/// A single exercise inside a Replay. Cues are authored content shipped
/// with the build — never AI-generated, never trainer-attributed (per
/// the locked spec; trainer attribution returns when cues are actually
/// trainer-reviewed at scale).
struct MayaExercise: Identifiable, Hashable {
    let id: UUID
    let name: String
    let sets: Int
    let reps: Int
    /// "25 lbs" — purely informational rendering hint on the set tracker.
    /// nil means weight is the user's call.
    let defaultWeightLabel: String?
    /// `formCues` plural in case a future revision splits cues per set;
    /// today every set inside an exercise shares one cue except the
    /// final-set variant in `finalSetCue`.
    let formCues: [String]
    let restCue: String
    let finalSetCue: String

    init(
        id: UUID = UUID(),
        name: String,
        sets: Int,
        reps: Int,
        defaultWeightLabel: String? = nil,
        formCues: [String],
        restCue: String,
        finalSetCue: String
    ) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.defaultWeightLabel = defaultWeightLabel
        self.formCues = formCues
        self.restCue = restCue
        self.finalSetCue = finalSetCue
    }

    /// Primary form cue rendered on the Active Replay set screen.
    var primaryFormCue: String { formCues.first ?? "" }
}

// MARK: - MayaWorkoutSession (transient runtime state)

/// In-flight session state while the user is moving through a Replay.
/// Pure struct held by `MayaMVPRootView` as `@State` — never persisted.
/// If the app closes mid-session, the v1 MVP intentionally drops the
/// run (Resume Card is in the deferred manifest).
struct MayaWorkoutSession {
    let id: UUID
    let replay: Replay
    var currentExerciseIndex: Int
    var currentSetIndex: Int
    var completedSets: [CompletedSetKey]
    var isResting: Bool
    var startedAt: Date
    var completedAt: Date?
    var state: State

    enum State: String, Codable {
        case active, resting, completed, abandoned
    }

    /// Compound key (exercise index, set index) used to mark a set done.
    struct CompletedSetKey: Hashable, Codable {
        let exerciseIndex: Int
        let setIndex: Int
    }

    init(replay: Replay) {
        self.id = UUID()
        self.replay = replay
        self.currentExerciseIndex = 0
        self.currentSetIndex = 0
        self.completedSets = []
        self.isResting = false
        self.startedAt = .init()
        self.completedAt = nil
        self.state = .active
    }

    // MARK: Computed helpers

    var currentExercise: MayaExercise {
        replay.exercises[currentExerciseIndex]
    }

    /// Elapsed seconds since the session started.
    var elapsedSeconds: Int {
        Int(Date().timeIntervalSince(startedAt))
    }

    /// "8 min in" — used in the Active Replay header. Rounded down so
    /// the time never reads ahead of what the user has actually done.
    var elapsedLabel: String {
        let minutes = max(0, elapsedSeconds / 60)
        return "\(minutes) min in"
    }

    /// True when the current set is the LAST set of the current exercise.
    var isFinalSet: Bool {
        currentSetIndex == currentExercise.sets - 1
    }

    /// True when the current exercise is the LAST one in the replay.
    var isFinalExercise: Bool {
        currentExerciseIndex == replay.exercises.count - 1
    }

    /// Display count of completed sets within the current exercise.
    var setsCompletedInCurrentExercise: Int {
        let exIdx = currentExerciseIndex
        return completedSets.filter { $0.exerciseIndex == exIdx }.count
    }

    /// All sets completed across the whole session.
    var totalCompletedSets: Int { completedSets.count }

    /// Distinct exercises with ≥1 completed set — used by SavedWin.
    var exercisesCompleted: Int {
        Set(completedSets.map(\.exerciseIndex)).count
    }
}

// MARK: - SavedWin (persisted)

/// One private saved win after the user taps Save Win on Shared Win.
/// `isPrivate` is true by default and there is no public path —
/// nothing in this MVP can flip it. Future audience UX is deferred.
@Model
final class SavedWin {
    @Attribute(.unique) var id: UUID
    var replayId: UUID
    var replayTitle: String
    var durationMinutes: Int
    var exercisesCompleted: Int
    var totalExercises: Int
    var savedAt: Date
    var isPrivate: Bool

    init(
        id: UUID = UUID(),
        replayId: UUID,
        replayTitle: String,
        durationMinutes: Int,
        exercisesCompleted: Int,
        totalExercises: Int,
        savedAt: Date = Date(),
        isPrivate: Bool = true
    ) {
        self.id = id
        self.replayId = replayId
        self.replayTitle = replayTitle
        self.durationMinutes = durationMinutes
        self.exercisesCompleted = exercisesCompleted
        self.totalExercises = totalExercises
        self.savedAt = savedAt
        self.isPrivate = isPrivate
    }
}

// MARK: - RunItBackState (persisted, single row)

/// Queues a replay to be the preselected option on next launch. NOT a
/// scheduled notification — there is no scheduling, no calendar item,
/// no reminder. Just a local hint that becomes the Cold Start default.
@Model
final class RunItBackState {
    @Attribute(.unique) var id: UUID
    var queuedReplayId: UUID?
    var queuedAt: Date?
    /// Single row gate — at most one RunItBackState exists per install.
    /// Used by the seeder to find-or-create on launch.
    var isReadyForNextOpen: Bool

    init(
        id: UUID = UUID(),
        queuedReplayId: UUID? = nil,
        queuedAt: Date? = nil,
        isReadyForNextOpen: Bool = false
    ) {
        self.id = id
        self.queuedReplayId = queuedReplayId
        self.queuedAt = queuedAt
        self.isReadyForNextOpen = isReadyForNextOpen
    }
}

// MARK: - NotificationPreferences (struct + UserDefaults adapter)

/// Notification opt-in flags. All default false. The MVP does NOT
/// request OS notification permission — that prompt is gated on the
/// user's first explicit opt-in elsewhere, not on launch.
struct NotificationPreferences: Codable {
    var friendActivity: Bool
    var liveFriendStarted: Bool
    var weeklyRecap: Bool
    var streakReminders: Bool

    static var allOff: NotificationPreferences {
        NotificationPreferences(
            friendActivity: false,
            liveFriendStarted: false,
            weeklyRecap: false,
            streakReminders: false
        )
    }

    var allFalse: Bool {
        !friendActivity && !liveFriendStarted && !weeklyRecap && !streakReminders
    }
}

// MARK: - PrivacyPreferences

/// Privacy defaults — private + no-strangers always on for the MVP.
struct PrivacyPreferences: Codable {
    var privateByDefault: Bool
    var noStrangers: Bool

    static var lockedDown: PrivacyPreferences {
        PrivacyPreferences(privateByDefault: true, noStrangers: true)
    }
}

// MARK: - ResearchEvent

/// One row in the lightweight research log. Held in-memory for the
/// session; debug builds can persist via `ResearchEventLogger`.
struct ResearchEvent: Codable {
    let timestamp: Date
    let sessionId: UUID
    let participantId: String?
    let eventName: String
    let metadata: [String: String]

    init(
        sessionId: UUID,
        participantId: String?,
        eventName: String,
        metadata: [String: String] = [:],
        timestamp: Date = Date()
    ) {
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.participantId = participantId
        self.eventName = eventName
        self.metadata = metadata
    }
}
