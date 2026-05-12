// MayaReplayLibrary — the static set of guided replays shipped with the
// validation MVP build. Five replays cover the five Cold Start chips.
//
// Per the locked spec, this content is shipped in-app (never authored
// by users, never fetched from a server in v1). The single source of
// truth for Cold Start chip selection: `MayaReplayLibrary.replay(for:)`.
//
// The default replay shown on first Cold Start render is `upperReset`
// (chip `.goodFirstLift`).

import Foundation

@MainActor
enum MayaReplayLibrary {

    /// Default replay surfaced when the user first opens the app with
    /// no Run-It-Back queue.
    static let defaultChip: ReplayChipType = .goodFirstLift

    /// All five replays. Order isn't user-visible.
    static let all: [Replay] = [
        upperReset,
        returningReset,
        lowerReset,
        upperResetUpperBody,
        quickReset
    ]

    /// Returns the replay associated with a chip. Same `Replay.id`
    /// across calls — held in module-level `let` so chip selection
    /// behaves identically per session.
    static func replay(for chip: ReplayChipType) -> Replay {
        switch chip {
        case .goodFirstLift:       return upperReset
        case .returningAfterBreak: return returningReset
        case .upperBody:           return upperResetUpperBody
        case .lowerBody:           return lowerReset
        case .quickLift:           return quickReset
        }
    }

    /// Find by ID — used by RunItBackState to rehydrate the queued
    /// replay on next launch. Falls back to default chip's replay
    /// when the ID can't be resolved (e.g. content version drift).
    static func replay(forId id: UUID) -> Replay {
        if let match = all.first(where: { $0.id == id }) { return match }
        return replay(for: defaultChip)
    }

    /// Which chip currently maps to a given Replay (used to highlight
    /// the right chip after a Run-It-Back rehydration).
    static func chip(for replay: Replay) -> ReplayChipType {
        ReplayChipType.allCases.first(where: { self.replay(for: $0).id == replay.id })
            ?? defaultChip
    }

    // MARK: - Replays

    /// Upper Reset — 5 exercises, 22 min, default surfaced replay.
    static let upperReset = Replay(
        title: "Upper Reset",
        durationMinutes: 22,
        tag: "good first lift",
        chipType: .goodFirstLift,
        cuePreviewText: "lower slow · stop before your shoulders shrug",
        exercises: [
            MayaExercise(
                name: "Dumbbell Press",
                sets: 3,
                reps: 12,
                defaultWeightLabel: "25 lbs",
                formCues: ["Lower slow. Stop before your shoulders shrug up."],
                restCue: "Roll your shoulders back. Same weight next set.",
                finalSetCue: "Last set. Smooth reps. Finish clean."
            ),
            MayaExercise(
                name: "Seated Row",
                sets: 3,
                reps: 10,
                formCues: ["Pull your elbows back. Keep your neck relaxed."],
                restCue: "Let your grip reset. Same pace next set.",
                finalSetCue: "Last set. Keep the pull smooth."
            ),
            MayaExercise(
                name: "Shoulder Press",
                sets: 3,
                reps: 10,
                formCues: ["Keep your ribs down. Press straight up."],
                restCue: "Breathe slow. Keep the next set clean.",
                finalSetCue: "Last set. Stop before form gets messy."
            ),
            MayaExercise(
                name: "Lat Pulldown",
                sets: 3,
                reps: 12,
                formCues: ["Pull toward your chest. Don't lean back too far."],
                restCue: "Shake out your arms. One clean set next.",
                finalSetCue: "Last set. Smooth pull, slow return."
            ),
            MayaExercise(
                name: "Bicep Curl",
                sets: 2,
                reps: 12,
                formCues: ["Keep your elbows still. Curl without swinging."],
                restCue: "Reset your grip. Finish easy.",
                finalSetCue: "Last set. Smooth reps. Finish clean."
            )
        ]
    )

    /// Returning Reset — for users coming back after a break. Lighter
    /// load, low-pressure cues.
    static let returningReset = Replay(
        title: "Returning Reset",
        durationMinutes: 20,
        tag: "low pressure",
        chipType: .returningAfterBreak,
        cuePreviewText: "start lighter than you think · make it easy to return",
        exercises: [
            MayaExercise(
                name: "Goblet Squat",
                sets: 3,
                reps: 10,
                formCues: ["Sit between your knees. Chest tall."],
                restCue: "Breathe slow. Keep the next set easy.",
                finalSetCue: "Last set. Smooth pace. Stop if form slips."
            ),
            MayaExercise(
                name: "Dumbbell Press",
                sets: 2,
                reps: 10,
                formCues: ["Start lighter than you think. Lower slow."],
                restCue: "Same weight next set. No need to push.",
                finalSetCue: "Last set. Keep it clean."
            ),
            MayaExercise(
                name: "Seated Row",
                sets: 2,
                reps: 10,
                formCues: ["Pull your elbows back. Light load is fine."],
                restCue: "Reset your grip. One easy set left.",
                finalSetCue: "Last set. Smooth and quiet."
            ),
            MayaExercise(
                name: "Glute Bridge",
                sets: 2,
                reps: 12,
                formCues: ["Squeeze at the top. Don't arch your back."],
                restCue: "Relax fully between sets.",
                finalSetCue: "Last set. Slow up, slow down."
            )
        ]
    )

    /// Upper Reset variant routed by the `.upperBody` chip — same
    /// content + same ID as `upperReset`, just labeled `upper body`.
    /// Sharing the underlying replay means saved wins and Run-It-Back
    /// state collapse correctly.
    static let upperResetUpperBody = Replay(
        id: upperReset.id,
        title: "Upper Reset",
        durationMinutes: 22,
        tag: "upper body",
        chipType: .upperBody,
        cuePreviewText: upperReset.cuePreviewText,
        exercises: upperReset.exercises
    )

    /// Lower Reset — steady lower-body session.
    static let lowerReset = Replay(
        title: "Lower Reset",
        durationMinutes: 24,
        tag: "steady lower",
        chipType: .lowerBody,
        cuePreviewText: "slow reps · keep your knees tracking forward",
        exercises: [
            MayaExercise(
                name: "Goblet Squat",
                sets: 3,
                reps: 10,
                formCues: ["Keep your knees tracking forward. Chest tall."],
                restCue: "Breathe slow. Set up clean next set.",
                finalSetCue: "Last set. Smooth pace. Stop if form slips."
            ),
            MayaExercise(
                name: "Romanian Deadlift",
                sets: 3,
                reps: 10,
                formCues: ["Hinge at the hips. Bar stays close to your legs."],
                restCue: "Reset your back. Same weight next set.",
                finalSetCue: "Last set. Slow descent, strong drive up."
            ),
            MayaExercise(
                name: "Walking Lunge",
                sets: 3,
                reps: 10,
                formCues: ["Front knee over your shoelaces. Step long."],
                restCue: "Shake out your legs. Steady pace next set.",
                finalSetCue: "Last set. Keep your torso tall the whole way."
            ),
            MayaExercise(
                name: "Glute Bridge",
                sets: 3,
                reps: 12,
                formCues: ["Squeeze at the top. Ribs stay down."],
                restCue: "Relax fully. One smooth set left.",
                finalSetCue: "Last set. Slow up, slow down."
            ),
            MayaExercise(
                name: "Calf Raise",
                sets: 2,
                reps: 15,
                formCues: ["Full range. Pause at the top."],
                restCue: "Stretch your calves. Finish easy.",
                finalSetCue: "Last set. Smooth reps. Finish clean."
            )
        ]
    )

    /// Quick Reset — 14-minute compressed lift for short-on-time days.
    static let quickReset = Replay(
        title: "Quick Reset",
        durationMinutes: 14,
        tag: "quick lift",
        chipType: .quickLift,
        cuePreviewText: "keep it simple · finish clean",
        exercises: [
            MayaExercise(
                name: "Dumbbell Press",
                sets: 2,
                reps: 10,
                formCues: ["Lower slow. Stop before your shoulders shrug up."],
                restCue: "Quick reset. One clean set left.",
                finalSetCue: "Last set. Smooth reps. Finish clean."
            ),
            MayaExercise(
                name: "Seated Row",
                sets: 2,
                reps: 10,
                formCues: ["Pull your elbows back. Keep your neck relaxed."],
                restCue: "Reset your grip. Same pace next set.",
                finalSetCue: "Last set. Keep the pull smooth."
            ),
            MayaExercise(
                name: "Goblet Squat",
                sets: 2,
                reps: 10,
                formCues: ["Chest tall. Sit between your knees."],
                restCue: "Breathe slow. Keep the next set clean.",
                finalSetCue: "Last set. Smooth pace. Finish clean."
            )
        ]
    )
}
