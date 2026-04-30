// StreakFlameBurst — content-psychology pass.
//
// Animation modifier that turns the static streak flame into a
// reactive moment. On `.workoutFinished` notification the flame
// swells, particles burst outward, and settles brighter. Intensity
// scales by milestone — day 7 small flare, day 30 medium, day 100
// real moment, day 365 distinct yearly burst.
//
// Drop-in: wrap any `StreakVisualBadge` in `.streakFlameBurst(days:)`.

import SwiftUI

extension View {
    /// Adds a milestone-aware burst animation that fires on
    /// `.workoutFinished` notifications. `days` is the streak length
    /// AFTER the workout completes — caller passes their post-save value.
    func streakFlameBurst(days: Int) -> some View {
        modifier(StreakFlameBurstModifier(days: days))
    }
}

private struct StreakFlameBurstModifier: ViewModifier {
    let days: Int
    @State private var bursting = false
    @State private var particles: [Particle] = []
    @State private var swell: CGFloat = 1.0

    private var milestone: Milestone {
        if days >= 365 { return .yearly }
        if days >= 100 { return .hundred }
        if days >= 30 { return .thirty }
        if days >= 7 { return .seven }
        return .none
    }

    func body(content: Content) -> some View {
        ZStack {
            content
                .scaleEffect(swell)

            ForEach(particles) { p in
                Image(systemName: "flame.fill")
                    .font(.system(size: p.size))
                    .foregroundStyle(p.color)
                    .opacity(p.opacity)
                    .offset(p.offset)
                    .allowsHitTesting(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .workoutFinished)) { _ in
            triggerBurst()
        }
    }

    private func triggerBurst() {
        let count = milestone.particleCount
        let radius = milestone.radius
        let duration = milestone.duration
        let baseSize = milestone.particleSize

        bursting = true
        particles = (0..<count).map { i in
            let angle = (Double(i) / Double(count)) * 2 * .pi
            let dist = radius * CGFloat.random(in: 0.6...1.0)
            return Particle(
                id: UUID(),
                size: baseSize * CGFloat.random(in: 0.6...1.0),
                color: milestone.particleColor,
                offset: .zero,
                opacity: 1.0,
                angle: angle,
                targetDist: dist
            )
        }

        // Phase 1 — particles fly outward + flame swells.
        withAnimation(.easeOut(duration: duration)) {
            swell = milestone.swellFactor
            for i in particles.indices {
                let angle = particles[i].angle
                let dist = particles[i].targetDist
                particles[i].offset = CGSize(
                    width: cos(angle) * dist,
                    height: sin(angle) * dist
                )
                particles[i].opacity = 0
            }
        }

        // Phase 2 — settle back, particles cleared.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                swell = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                particles = []
                bursting = false
            }
        }

        #if canImport(UIKit)
        // Tactile punctuation matched to the visual scale.
        switch milestone {
        case .yearly, .hundred:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .thirty, .seven:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .none:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        #endif
    }

    private struct Particle: Identifiable {
        let id: UUID
        let size: CGFloat
        let color: Color
        var offset: CGSize
        var opacity: Double
        let angle: Double
        let targetDist: CGFloat
    }

    private enum Milestone {
        case none, seven, thirty, hundred, yearly

        var particleCount: Int {
            switch self {
            case .none:   return 4
            case .seven:  return 8
            case .thirty: return 14
            case .hundred: return 22
            case .yearly: return 32
            }
        }
        var radius: CGFloat {
            switch self {
            case .none:   return 24
            case .seven:  return 36
            case .thirty: return 56
            case .hundred: return 80
            case .yearly: return 110
            }
        }
        var duration: Double {
            switch self {
            case .none:   return 0.55
            case .seven:  return 0.7
            case .thirty: return 0.95
            case .hundred: return 1.2
            case .yearly: return 1.5
            }
        }
        var swellFactor: CGFloat {
            switch self {
            case .none:   return 1.18
            case .seven:  return 1.30
            case .thirty: return 1.50
            case .hundred: return 1.75
            case .yearly: return 2.10
            }
        }
        var particleSize: CGFloat {
            switch self {
            case .none, .seven: return 12
            case .thirty:       return 16
            case .hundred:      return 20
            case .yearly:       return 24
            }
        }
        var particleColor: Color {
            switch self {
            case .none, .seven, .thirty: return Color.orange
            case .hundred:                return Color(red: 1.0, green: 0.55, blue: 0.18)
            case .yearly:                 return Color.yellow
            }
        }
    }
}
