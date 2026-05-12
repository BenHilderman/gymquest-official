// MayaMVPRootView — the entry point + state machine for the locked
// Maya MVP flow. Phase-driven: ColdStart → Active → Rest → SharedWin
// (completion) → SharedWin (saved) → back to Cold Start with the
// option to Run It Back (which preselects the same replay on next
// open).
//
// One root view owns the entire flow so transitions are cheap, no
// navigation stack pushes are exposed to testers (the v3 mockups
// are pageless — no back chrome anywhere except the pause button
// during a session).

import SwiftUI
import SwiftData

struct MayaMVPRootView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var phase: MVPPhase = .coldStart
    @State private var selectedChip: ReplayChipType = MayaReplayLibrary.defaultChip
    @State private var session: MayaWorkoutSession?
    @State private var lastSavedWin: SavedWin?
    @State private var didBootstrap: Bool = false

    enum MVPPhase: Equatable {
        case coldStart
        case active
        case rest
        case sharedWinCompletion
        case sharedWinSaved
    }

    var body: some View {
        ZStack {
            switch phase {
            case .coldStart:
                MayaColdStartView(
                    selectedChip: $selectedChip,
                    onStartReplay: startReplay
                )
                .transition(.opacity)

            case .active:
                if let session {
                    MayaActiveReplayView(
                        session: session,
                        onDidIt: handleDidIt,
                        onSkip: handleSkip,
                        onPause: handlePause
                    )
                    .transition(.opacity)
                }

            case .rest:
                if let session, let next = nextSetContext() {
                    MayaRestView(
                        session: session,
                        nextExercise: next.exercise,
                        nextSetIndex: next.setIndex,
                        onStartNextSet: handleStartNextSet,
                        onExtend: { /* extend = no-op; user can also just keep waiting */ },
                        onPause: handlePause
                    )
                    .transition(.opacity)
                }

            case .sharedWinCompletion:
                if let session {
                    MayaSharedWinView(
                        session: session,
                        state: .completion,
                        onSaveWin: handleSaveWin,
                        onNotNow: handleNotNow,
                        onRunItBack: { /* unreachable in completion state */ },
                        onTryAnother: { /* unreachable in completion state */ }
                    )
                    .transition(.opacity)
                }

            case .sharedWinSaved:
                if let session, let win = lastSavedWin {
                    MayaSharedWinView(
                        session: session,
                        state: .saved(win),
                        onSaveWin: { /* unreachable in saved state */ },
                        onNotNow: { /* unreachable in saved state */ },
                        onRunItBack: handleRunItBack,
                        onTryAnother: handleTryAnother
                    )
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.28), value: phase)
        .onAppear(perform: bootstrap)
    }

    // MARK: - Bootstrap

    /// Runs once per cold app launch.
    ///
    /// - Logs `app_opened` + (debug-only) `notification_default_off_verified`.
    /// - Consumes any queued Run-It-Back state so the Cold Start chip
    ///   reflects "what you saved yesterday."
    private func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        ResearchEventLogger.shared.log(.app_opened)

        // No OS notification request, no scheduled push. The MVP is
        // explicitly notification-off; log a confirmation event in
        // debug builds so the researcher can grep for it.
        #if DEBUG
        ResearchEventLogger.shared.log(.notification_default_off_verified, metadata: [
            "friendActivity": "false",
            "weeklyRecap": "false",
            "streakReminders": "false"
        ])
        #endif

        // Run-It-Back rehydration: if the user queued a replay last
        // session, preselect that chip on Cold Start now.
        if let queued = MayaSessionStore.peekQueuedReplayChip(in: modelContext) {
            selectedChip = queued
        }
    }

    // MARK: - Cold Start → Active

    private func startReplay() {
        let replay = MayaReplayLibrary.replay(for: selectedChip)
        let fresh = MayaWorkoutSession(replay: replay)
        session = fresh
        withAnimation { phase = .active }
    }

    // MARK: - Active → Rest / Active / SharedWin

    private func handleDidIt() {
        guard var working = session else { return }
        let key = MayaWorkoutSession.CompletedSetKey(
            exerciseIndex: working.currentExerciseIndex,
            setIndex: working.currentSetIndex
        )
        if !working.completedSets.contains(key) {
            working.completedSets.append(key)
        }
        ResearchEventLogger.shared.log(.set_completed, session: working)

        if working.isFinalSet {
            // Last set of the current exercise — advance exercise OR
            // finish the workout.
            ResearchEventLogger.shared.log(.exercise_completed, session: working)
            if working.isFinalExercise {
                working.completedAt = .init()
                working.state = .completed
                session = working
                ResearchEventLogger.shared.log(.workout_completed, session: working)
                withAnimation { phase = .sharedWinCompletion }
                return
            }
            working.currentExerciseIndex += 1
            working.currentSetIndex = 0
            session = working
            withAnimation { phase = .active }
            return
        }

        // More sets remain in this exercise — advance set index, head
        // to Rest.
        working.currentSetIndex += 1
        working.isResting = true
        working.state = .resting
        session = working
        withAnimation { phase = .rest }
    }

    private func handleSkip() {
        // Skip mirrors "I did it" for v1 — the set advances. Future
        // iterations may collect adjustment data here.
        handleDidIt()
    }

    private func handlePause() {
        // v1: pause is acknowledged but has no dedicated UI yet. Log
        // the event so we can spot users who pause repeatedly.
        guard let session else { return }
        ResearchEventLogger.shared.log(.session_abandoned, session: session, extra: [
            "trigger": "pause"
        ])
    }

    // MARK: - Rest → Active

    private func handleStartNextSet() {
        guard var working = session else { return }
        working.isResting = false
        working.state = .active
        session = working
        withAnimation { phase = .active }
    }

    /// Resolves "what's next" for the Rest screen — same exercise's
    /// next set unless we've already advanced.
    private func nextSetContext() -> (exercise: MayaExercise, setIndex: Int)? {
        guard let session else { return nil }
        return (session.currentExercise, session.currentSetIndex)
    }

    // MARK: - Shared Win

    private func handleSaveWin() {
        guard let session else { return }
        let win = MayaSessionStore.saveWin(from: session, in: modelContext)
        lastSavedWin = win
        withAnimation { phase = .sharedWinSaved }
    }

    private func handleNotNow() {
        // No save — drop the session, return to Cold Start.
        resetToColdStart()
    }

    private func handleRunItBack() {
        guard let session else { return }
        MayaSessionStore.queueRunItBack(session.replay, in: modelContext)
        // Stay on the Saved screen so the user sees the confirmation;
        // a tap anywhere else returns to Cold Start via Try Another.
        // The "Run It Back" tap itself is the queued intent — no
        // notification, no calendar item.
        // For v1 we route back to Cold Start with the saved replay
        // preselected as the proof.
        selectedChip = session.replay.chipType
        resetToColdStart()
    }

    private func handleTryAnother() {
        // User opted to try a different Maya replay — clear the queue
        // so the chip selection is fresh on next launch.
        MayaSessionStore.runItBackState(in: modelContext).queuedReplayId = nil
        MayaSessionStore.runItBackState(in: modelContext).isReadyForNextOpen = false
        try? modelContext.save()
        resetToColdStart()
    }

    private func resetToColdStart() {
        session = nil
        lastSavedWin = nil
        withAnimation { phase = .coldStart }
    }
}

// MARK: - Session store helper

extension MayaSessionStore {
    /// Returns the chip that maps to a currently-queued replay, if any.
    /// Used by `MayaMVPRootView.bootstrap` to preselect the right chip
    /// on the next Cold Start render.
    @MainActor
    static func peekQueuedReplayChip(in context: ModelContext) -> ReplayChipType? {
        guard let replay = peekQueuedReplay(in: context) else { return nil }
        return MayaReplayLibrary.chip(for: replay)
    }
}
