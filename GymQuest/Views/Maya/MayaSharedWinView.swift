// MayaSharedWinView — Screens 4 & 5 of the Maya MVP. Two states share
// this view: completion (post-workout, before Save Win is tapped) and
// saved (after the user persists the win + can Run It Back).
//
// Per the locked spec there is no public sharing, no Story, no Send,
// no friend reaction, no "Thank Maya". The only social bridge is the
// soft-green education line on the saved variant.

import SwiftUI

struct MayaSharedWinView: View {
    enum State {
        case completion
        case saved(SavedWin)
    }

    let session: MayaWorkoutSession
    let state: State
    let onSaveWin: () -> Void
    let onNotNow: () -> Void
    let onRunItBack: () -> Void
    let onTryAnother: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            eyebrow

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            ctaStack
                .padding(.bottom, 20)
                .padding(.horizontal, 20)
        }
        .background(MayaTokens.bg.ignoresSafeArea())
        .onAppear {
            switch state {
            case .completion:
                ResearchEventLogger.shared.log(.shared_win_viewed, session: session)
            case .saved:
                ResearchEventLogger.shared.log(.saved_screen_viewed, session: session)
            }
        }
    }

    // MARK: - Eyebrow

    private var eyebrow: some View {
        Text(eyebrowText)
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.2)
            .foregroundColor(MayaTokens.soft)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
    }

    private var eyebrowText: String {
        switch state {
        case .completion: return "REPLAY COMPLETE"
        case .saved:      return "WIN SAVED"
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch state {
        case .completion: completionContent
        case .saved(let win): savedContent(win: win)
        }
    }

    private var completionContent: some View {
        VStack(spacing: 0) {
            // 🫶 emoji moment
            Text("🫶")
                .font(.system(size: 56))
                .padding(.top, 16)
                .padding(.bottom, 4)
                .shadow(color: MayaTokens.pink.opacity(0.18), radius: 12, y: 4)

            // "You showed up" with gradient on "showed up"
            Text(headlineAttributed)
                .font(.system(size: 32, weight: .heavy))
                .tracking(-1.05)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.bottom, 12)

            Text("\(session.replay.title) · \(session.replay.durationMinutes) min")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MayaTokens.soft)
                .padding(.bottom, 14)

            Text("Save this win?")
                .font(.system(size: 12.5, weight: .heavy))
                .tracking(0.2)
                .foregroundColor(MayaTokens.muted)
                .padding(.bottom, 14)

            Text("save this so tomorrow starts here")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(MayaTokens.soft)
                .multilineTextAlignment(.center)
                .padding(.bottom, 14)
                .padding(.horizontal, 24)

            HStack(spacing: 5) {
                Text("🔒").font(.system(size: 10))
                Text("saved privately · only you can see this")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MayaTokens.muted)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(MayaTokens.text.opacity(0.03))
            )
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
    }

    /// Headline with the "showed up" portion painted with the warm
    /// brand gradient — matches the v3 mockup's accent treatment.
    private var headlineAttributed: AttributedString {
        var result = AttributedString("You ")
        result.foregroundColor = MayaTokens.text

        var accent = AttributedString("showed up")
        accent.foregroundColor = MayaTokens.violet  // gradient is text-only; pick the dominant warm color
        result.append(accent)
        return result
    }

    private func savedContent(win: SavedWin) -> some View {
        VStack(spacing: 0) {
            Text("Saved")
                .font(.system(size: 32, weight: .heavy))
                .tracking(-1.05)
                .foregroundColor(MayaTokens.text)
                .padding(.top, 24)
                .padding(.bottom, 12)

            Text("we'll keep it ready · tap when you open the app tomorrow")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(MayaTokens.soft)
                .multilineTextAlignment(.center)
                .padding(.bottom, 14)
                .padding(.horizontal, 24)

            savedCard(win: win)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            HStack(spacing: 5) {
                Text("🌿").font(.system(size: 11))
                Text("Friends can leave real replays later.")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(MayaTokens.muted)
            }
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
    }

    private func savedCard(win: SavedWin) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text("✓").font(.system(size: 11)).foregroundColor(MayaTokens.beg)
                Text("SAVED PRIVATELY")
                    .font(.system(size: 9.5, weight: .heavy))
                    .tracking(1.3)
                    .foregroundColor(MayaTokens.violet)
            }
            .padding(.bottom, 5)

            Text(win.replayTitle)
                .font(.system(size: 17, weight: .heavy))
                .tracking(-0.3)
                .foregroundColor(MayaTokens.text)
                .padding(.bottom, 3)

            Text("showed up · \(win.durationMinutes) min · \(win.exercisesCompleted)/\(win.totalExercises) exercises")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(MayaTokens.soft)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(MayaTokens.savedCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(MayaTokens.violet.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: - CTAs

    @ViewBuilder
    private var ctaStack: some View {
        switch state {
        case .completion:
            VStack(spacing: 8) {
                Button(action: handleSave) { Text("Save Win") }
                    .buttonStyle(MayaPrimaryButtonStyle(tone: .brand))
                    .accessibilityLabel("Save Win")
                Button(action: handleNotNow) { Text("Not now") }
                    .buttonStyle(MayaTertiaryButtonStyle())
                    .accessibilityLabel("Not now")
            }
        case .saved:
            VStack(spacing: 8) {
                Button(action: handleRunItBack) { Text("Run It Back") }
                    .buttonStyle(MayaPrimaryButtonStyle(tone: .warm))
                    .accessibilityLabel("Run It Back")
                Button(action: handleTryAnother) { Text("Try another Maya replay") }
                    .buttonStyle(MayaSecondaryButtonStyle())
                    .accessibilityLabel("Try another Maya replay")
            }
        }
    }

    // MARK: - Actions

    private func handleSave() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        ResearchEventLogger.shared.log(.save_win_tapped, session: session)
        onSaveWin()
    }

    private func handleNotNow() {
        ResearchEventLogger.shared.log(.not_now_tapped, session: session)
        onNotNow()
    }

    private func handleRunItBack() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        ResearchEventLogger.shared.log(.run_it_back_tapped, session: session)
        onRunItBack()
    }

    private func handleTryAnother() {
        ResearchEventLogger.shared.log(.try_another_replay_tapped, session: session)
        onTryAnother()
    }
}
