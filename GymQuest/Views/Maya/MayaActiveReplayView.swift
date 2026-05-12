// MayaActiveReplayView — Screen 2 of the Maya MVP. Renders the
// in-progress lift screen: header attribution, "now lifting" card,
// set indicator grid, Maya's form cue, and bottom-pinned "I did it"
// CTA.
//
// Two visual states share this view: standard set + final set. The
// final set toggle drives a stronger cue card variant and the
// gradient-tinted last-set indicator box.

import SwiftUI

struct MayaActiveReplayView: View {
    let session: MayaWorkoutSession
    let onDidIt: () -> Void
    let onSkip: () -> Void
    let onPause: () -> Void

    private var exercise: MayaExercise { session.currentExercise }
    private var isFinalSet: Bool { session.isFinalSet }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                nowLiftingCard
                    .padding(.top, 6)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
            Spacer(minLength: 0)
            ctaStack
                .padding(.bottom, 18)
        }
        .background(MayaTokens.bg.ignoresSafeArea())
        .onAppear {
            ResearchEventLogger.shared.log(.active_replay_viewed, session: session, extra: [
                "isFinalSet": isFinalSet ? "true" : "false"
            ])
        }
    }

    // MARK: - Header

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
                Text(progressSubtext)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(MayaTokens.soft)
            }
            .frame(maxWidth: .infinity)
            // Mirror padding so the title group stays optically centered
            // against the pause-only left button.
            .padding(.trailing, 38)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var progressSubtext: String {
        let exNum = session.currentExerciseIndex + 1
        let total = session.replay.totalExercises
        let suffix = isFinalSet ? "last set" : session.elapsedLabel
        return "exercise \(exNum) of \(total) · \(suffix)"
    }

    // MARK: - Now-lifting card

    private var nowLiftingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top accent stripe — 3pt Maya gradient.
            Rectangle()
                .fill(MayaTokens.mayaAvatar)
                .frame(height: 3)
                .padding(.bottom, 16)

            Text("⚡ NOW LIFTING")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.2)
                .foregroundColor(MayaTokens.soft)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            Text(exercise.name)
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.5)
                .foregroundColor(MayaTokens.text)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            // Demo tile is suppressed on the final-set screen per the
            // v3 mockup (drives focus toward finishing).
            if !isFinalSet {
                ExerciseDemoTile(
                    exerciseName: exercise.name,
                    hint: "quick look at the movement"
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            metaLine
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            setIndicators
                .padding(.horizontal, 16)
                .padding(.bottom, 16)

            cueBlock
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(MayaTokens.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(MayaTokens.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var metaLine: some View {
        let setNum = session.currentSetIndex + 1
        let totalSets = exercise.sets
        let suffix: String
        if isFinalSet {
            suffix = "this is the last one"
        } else if let weight = exercise.defaultWeightLabel {
            suffix = "last set: \(exercise.reps) × \(weight)"
        } else {
            suffix = ""
        }
        return Text(suffix.isEmpty
            ? "Set \(setNum) of \(totalSets) · \(exercise.reps) reps"
            : "Set \(setNum) of \(totalSets) · \(exercise.reps) reps · \(suffix)"
        )
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(MayaTokens.soft)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Three-up set indicator grid. State per box:
    ///   • `.done`   — completed set ("set 1 ✓ · 12 × 25")
    ///   • `.current`— active set ("set N · go")
    ///   • `.last`   — current AND final set ("last set · go")
    ///   • `.empty`  — not yet reached ("set N · —")
    private var setIndicators: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: min(exercise.sets, 3))
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(0..<exercise.sets, id: \.self) { idx in
                indicatorBox(for: idx)
            }
        }
    }

    private func indicatorBox(for idx: Int) -> some View {
        let state = boxState(for: idx)
        return VStack(spacing: 2) {
            Text(state.topLabel)
                .font(.system(size: 9.5, weight: .heavy))
                .tracking(0.5)
                .foregroundColor(state.topColor)
            Text(state.bottomLabel(reps: exercise.reps, weight: exercise.defaultWeightLabel))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(MayaTokens.text)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(state.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(state.borderColor, lineWidth: 1)
        )
    }

    private func boxState(for idx: Int) -> SetBoxState {
        if idx < session.currentSetIndex {
            return .done(idx: idx)
        } else if idx == session.currentSetIndex {
            return isFinalSet ? .last : .current(idx: idx)
        }
        return .empty(idx: idx)
    }

    private var cueBlock: some View {
        let label = isFinalSet ? "maya's form cue · last set" : "maya's form cue"
        let body = isFinalSet ? exercise.finalSetCue : exercise.primaryFormCue
        return CueCard(
            variant: isFinalSet ? .finalSet : .standard,
            label: label,
            body_: body
        )
    }

    // MARK: - CTA stack

    private var ctaStack: some View {
        VStack(spacing: 4) {
            Button(action: handleDidIt) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .heavy))
                    Text("I did it")
                        .font(.system(size: 18, weight: .heavy))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(
                    Capsule().fill(MayaTokens.brand)
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.24), lineWidth: 0.5)
                        .blendMode(.overlay)
                )
                .shadow(color: MayaTokens.violet.opacity(0.32), radius: 14, y: 4)
                .shadow(color: MayaTokens.pink.opacity(0.22), radius: 26, y: 12)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .accessibilityLabel("I did it")

            Button(action: handleSkip) {
                Text("skip · adjust weight")
            }
            .buttonStyle(MayaTertiaryButtonStyle())
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Actions

    private func handleDidIt() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        onDidIt()
    }

    private func handleSkip() {
        ResearchEventLogger.shared.log(.skip_adjust_tapped, session: session)
        onSkip()
    }
}

// MARK: - Set indicator box state

private enum SetBoxState {
    case done(idx: Int)
    case current(idx: Int)
    case last
    case empty(idx: Int)

    var topLabel: String {
        switch self {
        case .done(let idx):    return "SET \(idx + 1) ✓"
        case .current(let idx): return "SET \(idx + 1)"
        case .last:             return "LAST SET"
        case .empty(let idx):   return "SET \(idx + 1)"
        }
    }

    func bottomLabel(reps: Int, weight: String?) -> String {
        switch self {
        case .done:
            if let weight = weight {
                return "\(reps) × \(weight.replacingOccurrences(of: " lbs", with: ""))"
            }
            return "\(reps) reps"
        case .current, .last: return "go"
        case .empty: return "—"
        }
    }

    var topColor: Color {
        switch self {
        case .done: return MayaTokens.beg
        case .current: return Color(red: 0x87 / 255, green: 0x6B / 255, blue: 0xBE / 255)
        case .last: return MayaTokens.violet
        case .empty: return MayaTokens.muted
        }
    }

    var background: Color {
        switch self {
        case .done:    return MayaTokens.beg.opacity(0.05)
        case .current: return MayaTokens.mayaAvatarEnd.opacity(0.07)
        case .last:    return MayaTokens.violet.opacity(0.07)
        case .empty:   return Color(red: 0xFB / 255, green: 0xF9 / 255, blue: 0xFC / 255)
        }
    }

    var borderColor: Color {
        switch self {
        case .done:    return MayaTokens.beg.opacity(0.24)
        case .current: return MayaTokens.mayaAvatarEnd.opacity(0.32)
        case .last:    return MayaTokens.violet.opacity(0.32)
        case .empty:   return MayaTokens.border
        }
    }
}
