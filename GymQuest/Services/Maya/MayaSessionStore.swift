// MayaSessionStore — thin SwiftData adapter for the Maya MVP's two
// persisted models: SavedWin (one row per saved completion) and
// RunItBackState (singleton row holding the queued replay for next
// launch).
//
// Why a service vs. raw modelContext calls: the read/write pattern is
// the same at every call site (find-or-create the singleton, append
// the win, clear the queue) and centralizing it keeps the view layer
// free of FetchDescriptor boilerplate.

import Foundation
import SwiftData

@MainActor
enum MayaSessionStore {

    // MARK: - SavedWin

    /// Persist a private SavedWin for a completed session. Returns the
    /// row so the caller can pass it to downstream UI if needed.
    @discardableResult
    static func saveWin(from session: MayaWorkoutSession, in context: ModelContext) -> SavedWin {
        let win = SavedWin(
            replayId: session.replay.id,
            replayTitle: session.replay.title,
            durationMinutes: session.replay.durationMinutes,
            exercisesCompleted: session.exercisesCompleted,
            totalExercises: session.replay.totalExercises,
            savedAt: .init(),
            isPrivate: true
        )
        context.insert(win)
        try? context.save()
        return win
    }

    /// All saved wins, newest first. The MVP doesn't surface a list
    /// page yet, but the data is available for the researcher's
    /// inspection during testing.
    static func recentWins(limit: Int = 10, in context: ModelContext) -> [SavedWin] {
        var descriptor = FetchDescriptor<SavedWin>(
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - RunItBackState (singleton)

    /// Find-or-create the single RunItBackState row. The MVP only ever
    /// has one — collapsing on a stable predicate avoids duplicates.
    @discardableResult
    static func runItBackState(in context: ModelContext) -> RunItBackState {
        let descriptor = FetchDescriptor<RunItBackState>()
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let fresh = RunItBackState()
        context.insert(fresh)
        try? context.save()
        return fresh
    }

    /// Queue a replay for the next launch's Cold Start. Idempotent;
    /// repeated calls overwrite the previous queued replay.
    static func queueRunItBack(_ replay: Replay, in context: ModelContext) {
        let state = runItBackState(in: context)
        state.queuedReplayId = replay.id
        state.queuedAt = .init()
        state.isReadyForNextOpen = true
        try? context.save()
    }

    /// Consume the queued replay (returns it + clears the queue). The
    /// MVP root calls this on launch to pick the initial chip.
    static func consumeQueuedReplay(in context: ModelContext) -> Replay? {
        let state = runItBackState(in: context)
        guard state.isReadyForNextOpen, let queuedId = state.queuedReplayId else {
            return nil
        }
        let replay = MayaReplayLibrary.replay(forId: queuedId)
        state.queuedReplayId = nil
        state.queuedAt = nil
        state.isReadyForNextOpen = false
        try? context.save()
        return replay
    }

    /// Peek at the queued replay without consuming it.
    static func peekQueuedReplay(in context: ModelContext) -> Replay? {
        let state = runItBackState(in: context)
        guard state.isReadyForNextOpen, let queuedId = state.queuedReplayId else {
            return nil
        }
        return MayaReplayLibrary.replay(forId: queuedId)
    }

    /// Reset both Maya-MVP-owned tables. Wired to a debug-only reset
    /// affordance for the researcher running back-to-back test
    /// sessions on the same install.
    static func resetMVPState(in context: ModelContext) {
        if let wins = try? context.fetch(FetchDescriptor<SavedWin>()) {
            wins.forEach { context.delete($0) }
        }
        if let states = try? context.fetch(FetchDescriptor<RunItBackState>()) {
            states.forEach { context.delete($0) }
        }
        try? context.save()
    }
}
