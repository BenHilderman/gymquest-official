// CalendarTileFillAnimation — content-psychology pass.
//
// Wraps a calendar day cell with a fill choreography:
//   • Today, untrained:  subtle gradient breath (pulsing low-opacity stroke)
//   • On `.workoutFinished` for today: brand-gradient sweep + scale punch
//     + brief glow halo, then settles into the "trained" filled state
//   • Today, already trained: stable filled state, no animation
//   • Other days: pass through (unchanged)
//
// Drop-in: replace your today-cell with `CalendarTileFillAnimation(...)`
// or wrap an existing cell via the `.calendarFillOnSave(isToday:trained:)`
// modifier.

import SwiftUI

struct CalendarTileFillAnimation: View {
    let date: Date
    let isTrainedToday: Bool
    var content: AnyView

    @State private var sweepProgress: CGFloat = 0
    @State private var scalePunch: CGFloat = 1.0
    @State private var glow: Double = 0
    @State private var breathAmount: Double = 0
    @State private var hasFilled: Bool

    init(date: Date, isTrainedToday: Bool, @ViewBuilder content: () -> some View) {
        self.date = date
        self.isTrainedToday = isTrainedToday
        self.content = AnyView(content())
        _hasFilled = State(initialValue: isTrainedToday)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        ZStack {
            // Underlying cell content.
            content

            // Empty-today breath: a low-opacity stroke that subtly pulses
            // so the user clocks "today is open" without it being noisy.
            if isToday && !hasFilled {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(GQGradients.primary, lineWidth: 1.5)
                    .opacity(0.25 + breathAmount * 0.4)
                    .scaleEffect(1.0 + breathAmount * 0.04)
                    .onAppear { startBreath() }
            }

            // Sweep fill — left-to-right brand gradient that draws across
            // the cell on save. Implemented as a clipped rectangle whose
            // width animates from 0 → 1 of the cell width.
            if isToday && sweepProgress > 0 {
                GeometryReader { geo in
                    Rectangle()
                        .fill(GQGradients.primary)
                        .frame(width: geo.size.width * sweepProgress, height: geo.size.height)
                        .opacity(0.85)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .blendMode(.normal)
                        .allowsHitTesting(false)
                }
            }

            // Glow halo — brief warm bloom right after sweep completes.
            if isToday && glow > 0 {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(GQGradients.primary, lineWidth: 2)
                    .blur(radius: 6)
                    .opacity(glow)
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(scalePunch)
        .onReceive(NotificationCenter.default.publisher(for: .workoutFinished)) { _ in
            guard isToday, !hasFilled else { return }
            playFillChoreography()
        }
    }

    private func startBreath() {
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            breathAmount = 1.0
        }
    }

    /// Three-beat fill choreography on save:
    ///   beat 1 (0–60ms): scale punch — feels tactile
    ///   beat 2 (0–550ms): sweep fill — left-to-right brand wash
    ///   beat 3 (450–950ms): glow halo — settles
    private func playFillChoreography() {
        // Scale punch
        withAnimation(.spring(response: 0.18, dampingFraction: 0.55)) {
            scalePunch = 1.18
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.65)) {
                scalePunch = 1.0
            }
        }

        // Sweep fill
        withAnimation(.easeInOut(duration: 0.55)) {
            sweepProgress = 1.0
        }

        // Glow + settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.easeInOut(duration: 0.4)) {
                glow = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.3)) {
                    glow = 0
                }
                hasFilled = true
                breathAmount = 0
            }
        }

        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
    }
}

extension View {
    /// Inline modifier — wraps the receiver as the calendar tile
    /// content for a given day. Use this to upgrade an existing cell
    /// without restructuring the calendar grid.
    func calendarFillOnSave(date: Date, isTrainedToday: Bool) -> some View {
        CalendarTileFillAnimation(
            date: date,
            isTrainedToday: isTrainedToday
        ) {
            self
        }
    }
}
