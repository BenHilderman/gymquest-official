// MayaRestView — Screen 3 of the Maya MVP. Between-set rest screen
// with countdown timer, Maya's note, and an "up next" preview.
//
// Per the locked spec: no notifications, no fake presence, no friend
// reactions, no music. Timer can be started early or extended.

import SwiftUI

struct MayaRestView: View {
    let session: MayaWorkoutSession
    let nextExercise: MayaExercise
    let nextSetIndex: Int
    let onStartNextSet: () -> Void
    let onExtend: () -> Void
    let onPause: () -> Void

    /// Rest period length — per the spec example (0:42). Counts down
    /// but never blocks: user can start the next set at any moment.
    private static let restDurationSeconds: Int = 42

    @State private var remainingSeconds: Int = MayaRestView.restDurationSeconds
    @State private var timer: Timer?
    @State private var startedAt: Date = .init()

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                timerSection
                noteSection
                upNextSection
                    .padding(.bottom, 14)
            }
            Spacer(minLength: 0)
            ctaStack
                .padding(.bottom, 18)
        }
        .background(MayaTokens.bg.ignoresSafeArea())
        .onAppear {
            ResearchEventLogger.shared.log(.rest_started, session: session, extra: [
                "restDurationSeconds": "\(Self.restDurationSeconds)"
            ])
            startedAt = .init()
            beginCountdown()
        }
        .onDisappear { invalidateTimer() }
    }

    // MARK: - Header (mirrors Active Replay shape but shows "resting between sets")

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onPause) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(MayaTokens.text)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(MayaTokens.text.opacity(0.05)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pause replay")

            VStack(spacing: 3) {
                HStack(spacing: 6) {
                    MayaAvatar(.xs)
                    Text("Maya · \(session.replay.title)")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(MayaTokens.text)
                }
                Text("resting between sets")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MayaTokens.soft)
            }
            .frame(maxWidth: .infinity)
            .padding(.trailing, 38)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Timer

    private var timerSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                MayaAvatar(.xs)
                Text("MAYA'S PACE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.4)
                    .foregroundColor(Color(red: 0x75 / 255, green: 0x58 / 255, blue: 0xA8 / 255))
            }
            .padding(.top, 12)

            timerRing

            paceLine
                .padding(.top, 2)
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    private var timerRing: some View {
        ZStack {
            // Outer conic gradient — fills from -90° clockwise per
            // current progress. Trim factor goes 1 → 0 as time ticks
            // down.
            Circle()
                .trim(from: 0, to: progressFraction)
                .stroke(
                    AngularGradient(
                        colors: [MayaTokens.violet, MayaTokens.pink, MayaTokens.violet],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 170, height: 170)
                .background(
                    Circle()
                        .stroke(MayaTokens.hairline, lineWidth: 9)
                        .frame(width: 170, height: 170)
                )

            Text(timerText)
                .font(.system(size: 46, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .tracking(-2)
                .foregroundColor(MayaTokens.text)
        }
        .frame(width: 170, height: 170)
    }

    private var progressFraction: Double {
        guard Self.restDurationSeconds > 0 else { return 0 }
        return Double(remainingSeconds) / Double(Self.restDurationSeconds)
    }

    private var timerText: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var paceLine: some View {
        HStack(spacing: 5) {
            Text("rest here")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(MayaTokens.text)
            Text("· one clean set left")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(MayaTokens.soft)
        }
    }

    // MARK: - Maya's note (uses current exercise's rest cue)

    private var noteSection: some View {
        HStack(alignment: .top, spacing: 10) {
            MayaAvatar(.sm)
            VStack(alignment: .leading, spacing: 3) {
                Text("MAYA'S NOTE")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.2)
                    .foregroundColor(Color(red: 0x75 / 255, green: 0x58 / 255, blue: 0xA8 / 255))
                Text(session.currentExercise.restCue)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(MayaTokens.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        MayaTokens.mayaAvatarStart.opacity(0.06),
                        MayaTokens.mayaAvatarEnd.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(MayaTokens.mayaAvatarEnd.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    // MARK: - Up Next preview

    private var upNextSection: some View {
        HStack(spacing: 11) {
            // Static demo silhouette — non-motion variant per spec
            // (.demo rm equivalent).
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 54, height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MayaTokens.border, lineWidth: 1)
                    )
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 22))
                    .foregroundColor(MayaTokens.soft)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("UP NEXT")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.1)
                    .foregroundColor(MayaTokens.muted)
                Text("\(nextExercise.name) · set \(nextSetIndex + 1)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(MayaTokens.text)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(MayaTokens.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MayaTokens.border, lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    // MARK: - CTAs

    private var ctaStack: some View {
        VStack(spacing: 4) {
            Button(action: handleStartNext) {
                HStack(spacing: 6) {
                    Text("Start set \(nextSetIndex + 1)")
                    Text("→").font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(MayaTokens.violet)
                .font(.system(size: 16, weight: .heavy))
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    Capsule().fill(MayaTokens.violet.opacity(0.09))
                )
                .overlay(
                    Capsule().stroke(MayaTokens.violet.opacity(0.38), lineWidth: 1)
                )
                .shadow(color: MayaTokens.violet.opacity(0.10), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .accessibilityLabel("Start set \(nextSetIndex + 1)")

            Button(action: handleExtend) {
                Text("rest a bit longer")
            }
            .buttonStyle(MayaTertiaryButtonStyle())
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Timer machinery

    private func beginCountdown() {
        invalidateTimer()
        remainingSeconds = Self.restDurationSeconds
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                guard remainingSeconds > 0 else {
                    invalidateTimer()
                    ResearchEventLogger.shared.log(.rest_completed, session: session)
                    return
                }
                remainingSeconds -= 1
            }
        }
    }

    private func invalidateTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Actions

    private func handleStartNext() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        invalidateTimer()
        let elapsed = Int(Date().timeIntervalSince(startedAt))
        ResearchEventLogger.shared.log(.next_set_started, session: session, extra: [
            "elapsedRestSeconds": "\(elapsed)"
        ])
        onStartNextSet()
    }

    private func handleExtend() {
        ResearchEventLogger.shared.log(.rest_extended, session: session)
        onExtend()
    }
}
