// FirstStrengthMilestoneService — content-psychology pass.
//
// Detects user-meaningful "first time" strength moments and exposes them
// as celebration cards. PR detection in PRService is great for repeated
// progress; this service is specifically about the *first* time you hit
// a number that means something culturally — first pull-up, first plate
// bench, first plate hip thrust, first 100lb deadlift, etc.
//
// Why a separate service:
//   - These milestones are universal-but-celebrated (research shows
//     they're bigger psychological moments for women newer to lifting,
//     where base strength makes them harder to hit early)
//   - Persisted "seen" state per milestone — fires once, ever
//   - Not all are 1RM; some are "first rep" (pull-ups)
//
// Detection runs after PRService so we use already-computed top sets.

import Foundation
import SwiftData

/// Catalog of celebrated "first time" strength milestones. Each is a
/// pure check function over the user's workout history.
enum FirstStrengthMilestone: String, CaseIterable, Identifiable {
    case firstPullUp                  // first rep of pull-up / chin-up
    case firstPlateBench              // 45kg/100lb bench (1 rep+)
    case bodyweightSquat              // 1RM squat ≥ bodyweight
    case firstPlateDeadlift           // 100lb / 45kg deadlift (1 rep+)
    case firstPlateHipThrust          // 100lb / 45kg hip thrust (1 rep+)
    case hundredKgHipThrust           // 100kg / 220lb hip thrust
    case bodyweightBenchPress         // 1RM bench ≥ bodyweight

    var id: String { rawValue }

    /// Identity-stamping copy for the milestone card.
    var celebrationLine: String {
        switch self {
        case .firstPullUp:           return "first pull-up"
        case .firstPlateBench:       return "a plate on bench"
        case .bodyweightSquat:       return "bodyweight squat"
        case .firstPlateDeadlift:    return "a plate off the floor"
        case .firstPlateHipThrust:   return "a plate hip thrust"
        case .hundredKgHipThrust:    return "100kg hip thrust"
        case .bodyweightBenchPress:  return "bodyweight bench"
        }
    }

    var subtitle: String {
        switch self {
        case .firstPullUp:           return "you can do them now."
        case .firstPlateBench:       return "100 lb / 45 kg. you're past beginner numbers."
        case .bodyweightSquat:       return "you can squat your own body. that's a real number."
        case .firstPlateDeadlift:    return "you pulled a plate. respect."
        case .firstPlateHipThrust:   return "leg-day momentum."
        case .hundredKgHipThrust:    return "100 kg. that's a serious hip thrust."
        case .bodyweightBenchPress:  return "you can press what you weigh."
        }
    }

    /// UserDefaults key recording this milestone has been celebrated.
    var seenKey: String { "firstStrengthMilestoneSeen-\(rawValue)" }
    var hasBeenSeen: Bool { UserDefaults.standard.bool(forKey: seenKey) }
    func markSeen() { UserDefaults.standard.set(true, forKey: seenKey) }

    /// Substring match against exercise names for milestone detection.
    /// Lowercased contains check — handles "Pull-up", "Pullup", etc.
    var exerciseNameMatchers: [String] {
        switch self {
        case .firstPullUp:
            return ["pull-up", "pullup", "pull up", "chin-up", "chinup", "chin up"]
        case .firstPlateBench, .bodyweightBenchPress:
            return ["bench press"]
        case .bodyweightSquat:
            return ["squat", "back squat", "high bar squat", "low bar squat"]
        case .firstPlateDeadlift:
            return ["deadlift", "conventional deadlift", "sumo deadlift"]
        case .firstPlateHipThrust, .hundredKgHipThrust:
            return ["hip thrust", "barbell hip thrust"]
        }
    }
}

@MainActor
enum FirstStrengthMilestoneService {

    /// Scan a user's workouts for newly-cleared first-strength milestones.
    /// Returns the milestones that fired *this scan* — caller surfaces
    /// celebration cards for each. Idempotent — already-seen milestones
    /// don't re-fire.
    static func newlyAchievedMilestones(
        userBodyweightLb: Double?,
        in context: ModelContext
    ) -> [FirstStrengthMilestone] {
        let descriptor = FetchDescriptor<Workout>()
        let allWorkouts = (try? context.fetch(descriptor)) ?? []
        guard !allWorkouts.isEmpty else { return [] }

        var fired: [FirstStrengthMilestone] = []
        for milestone in FirstStrengthMilestone.allCases where !milestone.hasBeenSeen {
            if check(milestone: milestone, workouts: allWorkouts, userBodyweightLb: userBodyweightLb) {
                milestone.markSeen()
                fired.append(milestone)
            }
        }
        return fired
    }

    private static func check(
        milestone: FirstStrengthMilestone,
        workouts: [Workout],
        userBodyweightLb: Double?
    ) -> Bool {
        // Find any matching exercise rows.
        let matchingExercises = workouts.flatMap { workout in
            workout.exercises.filter { ex in
                let lower = ex.name.lowercased()
                return milestone.exerciseNameMatchers.contains { lower.contains($0) }
            }
        }
        guard !matchingExercises.isEmpty else { return false }

        switch milestone {
        case .firstPullUp:
            // Any rep counts (bodyweight pulls = 0 weight; we just need reps).
            return matchingExercises.contains { ex in
                ex.sets.contains { $0.reps > 0 }
            }
        case .firstPlateBench, .firstPlateDeadlift, .firstPlateHipThrust:
            return topWeightLb(matchingExercises) >= 100
        case .hundredKgHipThrust:
            return topWeightLb(matchingExercises) >= 220   // 100 kg ≈ 220.46 lb
        case .bodyweightSquat, .bodyweightBenchPress:
            guard let bw = userBodyweightLb, bw > 0 else { return false }
            return topWeightLb(matchingExercises) >= bw
        }
    }

    /// Highest weight (in pounds) lifted across these exercises.
    /// Sets store weight in the user's preferred unit; for now treat
    /// it as pounds since the Workout model doesn't tag unit per set.
    private static func topWeightLb(_ exercises: [Exercise]) -> Double {
        exercises
            .flatMap { $0.sets }
            .map { $0.weight }
            .max() ?? 0
    }
}
