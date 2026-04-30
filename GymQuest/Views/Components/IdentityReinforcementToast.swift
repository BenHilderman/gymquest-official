// IdentityReinforcementToast — content-psychology pass.
//
// Replaces the post-save success notification with present-tense identity
// copy. The literature on habit formation (BJ Fogg + Atomic Habits) is
// clear: the most reinforcing reward is the *immediate* identity stamp.
// "you're a 47-time lifter" cements the behavior far more than "Workout
// Saved." Tier-keyed off streak length + lifetime workout count.
//
// Lift AI's voice rules apply — no BEAST MODE, no all-caps. Quiet,
// factual, present-tense.

import SwiftUI

struct IdentityReinforcementToast: View {
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(GQGradients.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(GQColors.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(GQColors.surfaceSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(GQColors.borderDefault, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
}

/// Resolves the identity copy from streak + workout count. Pure
/// function so it's trivial to unit-test and swap in alt voices later.
enum IdentityCopy {
    /// Returns (headline, optional subtitle) for the post-save toast.
    /// Headline is identity-stamping ("you showed up"). Subtitle is the
    /// quiet stat that backs it up.
    static func headline(streakDays: Int, totalWorkouts: Int) -> (String, String?) {
        // Year+ — distinct yearly identity
        if streakDays >= 365 {
            return ("you're built different", "day \(streakDays)")
        }
        if streakDays == 365 {
            return ("a year in", "respect")
        }
        // 100+ — committed
        if streakDays >= 100 {
            return ("you're committed", "day \(streakDays)")
        }
        if streakDays == 100 {
            return ("100 days", "you're committed")
        }
        // 30+ — consistent
        if streakDays >= 30 {
            return ("you're consistent", "day \(streakDays)")
        }
        if streakDays == 30 {
            return ("30 days", "you're consistent")
        }
        // 7+ — habitual
        if streakDays >= 7 {
            return ("you're a habitual lifter", "day \(streakDays)")
        }
        if streakDays == 7 {
            return ("a full week", "you're building this")
        }
        // 1+ — building it
        if streakDays >= 2 {
            return ("you showed up", "day \(streakDays)")
        }
        // Day 1
        if streakDays == 1 {
            return ("day 1 — here we go", nil)
        }
        // 50+ workouts but no streak — returning
        if totalWorkouts >= 50 {
            return ("welcome back", "session \(totalWorkouts)")
        }
        // First workout ever
        if totalWorkouts <= 1 {
            return ("first one in the books", "you're a lifter now")
        }
        // Default — neutral identity copy
        return ("you showed up", "session \(totalWorkouts)")
    }
}
