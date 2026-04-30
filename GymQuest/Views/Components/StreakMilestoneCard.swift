// StreakIdentityMilestoneCard — content-psychology pass.
//
// Quiet identity-stamping landing card that fires once per streak
// milestone (7 / 30 / 100 / 365). Persists "seen" state in UserDefaults
// so it never repeats per milestone. Shows present-tense identity copy
// + a single share affordance.
//
// Voice rule per locked spec: lowercase, factual, no caps, no hype.

import SwiftUI

struct StreakIdentityMilestoneCard: View {
    let milestone: StreakMilestone
    var onDismiss: () -> Void = {}
    var onShare: () -> Void = {}

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "flame.fill")
                .font(.system(size: 56))
                .foregroundStyle(GQGradients.primary)
                .scaleEffect(1.0)
                .modifier(MilestonePulse())

            VStack(spacing: 6) {
                Text(milestone.headline)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(GQColors.textPrimary)
                    .multilineTextAlignment(.center)
                Text(milestone.identityLine)
                    .font(.system(size: 15))
                    .foregroundColor(GQColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            HStack(spacing: 10) {
                Button("share") { onShare() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .frame(width: 110, height: 46)
                    .background(GQColors.adaptiveOverlay(0.06), in: Capsule())

                Button("got it") { onDismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .frame(width: 140)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(GQColors.surfaceBase)
    }
}

private struct MilestonePulse: ViewModifier {
    @State private var scale: CGFloat = 1.0
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    scale = 1.06
                }
            }
    }
}

enum StreakMilestone: Int, Identifiable {
    case seven = 7
    case thirty = 30
    case hundred = 100
    case yearly = 365

    var id: Int { rawValue }

    var headline: String {
        switch self {
        case .seven:   return "a full week"
        case .thirty:  return "30 days"
        case .hundred: return "100 days"
        case .yearly:  return "a year in"
        }
    }

    var identityLine: String {
        switch self {
        case .seven:   return "you're building this. day 7 — show up for day 8."
        case .thirty:  return "you're consistent. that's the part most people never reach."
        case .hundred: return "you're committed. one hundred days of showing up."
        case .yearly:  return "365 days. you're built different now."
        }
    }

    /// UserDefaults key that records this milestone has been shown.
    /// We never want to celebrate the same milestone twice.
    var seenKey: String { "streakMilestoneSeen-\(rawValue)" }

    /// Has the user seen this milestone card before?
    var hasBeenSeen: Bool {
        UserDefaults.standard.bool(forKey: seenKey)
    }

    func markSeen() {
        UserDefaults.standard.set(true, forKey: seenKey)
    }

    /// Resolves the milestone (if any) for a given streak day count.
    /// Returns nil when the day isn't a milestone or when the milestone
    /// has already been shown.
    static func current(for streakDays: Int) -> StreakMilestone? {
        guard let m = StreakMilestone(rawValue: streakDays) else { return nil }
        return m.hasBeenSeen ? nil : m
    }
}
