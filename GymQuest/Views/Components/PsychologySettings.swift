// PsychologySettings — content-psychology pass.
//
// Three settings rows that bundle together because they share theme:
//   • NoStrangersToggle — single switch hard-locks audience to friends/squad
//   • CoachToneRow — picks how the coach talks (supportive / neutral /
//     hype / educational / data-only)
//   • CyclePhaseRow — wraps CyclePhaseChip in a settings list row
//
// Caller is the user's existing SettingsView. Each row reads from /
// writes to the user's UserProfile via @Bindable.

import SwiftUI

struct NoStrangersToggleRow: View {
    @Bindable var profile: UserProfile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 16))
                .foregroundColor(GQColors.textPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("no strangers")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(GQColors.textPrimary)
                Text("hard-lock posts + stories to friends / squad only")
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
            }
            Spacer()
            Toggle("", isOn: $profile.noStrangersMode)
                .labelsHidden()
                .tint(GQColors.vividPurple)
        }
        .padding(.vertical, 10)
    }
}

struct CoachToneRow: View {
    @Bindable var profile: UserProfile
    @State private var showingPicker = false

    private let tones: [(value: String, label: String, blurb: String)] = [
        ("supportive", "supportive", "warm encouragement, soft tone"),
        ("neutral", "neutral", "factual, no hype, no fluff"),
        ("hype", "hype", "energetic, motivational"),
        ("educational", "educational", "form cues, why-this-matters explanations"),
        ("data", "data only", "just numbers, no commentary")
    ]

    var body: some View {
        Button { showingPicker = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.fill.viewfinder")
                    .font(.system(size: 16))
                    .foregroundColor(GQColors.textPrimary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text("coach tone")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(GQColors.textPrimary)
                    Text(currentLabel)
                        .font(.system(size: 11))
                        .foregroundColor(GQColors.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .confirmationDialog("coach tone", isPresented: $showingPicker, titleVisibility: .visible) {
            ForEach(tones, id: \.value) { tone in
                Button(tone.label) { profile.coachTone = tone.value }
            }
            Button("cancel", role: .cancel) {}
        } message: {
            Text("how should the coach talk to you?")
        }
    }

    private var currentLabel: String {
        tones.first(where: { $0.value == profile.coachTone })?.blurb
            ?? "factual, no hype, no fluff"
    }
}

struct CyclePhaseSettingsRow: View {
    @Bindable var profile: UserProfile

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 16))
                .foregroundColor(GQColors.textPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("phase tracking")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(GQColors.textPrimary)
                Text("on-device only · never synced anywhere")
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
            }
            Spacer()
            CyclePhaseChip(currentPhase: $profile.currentCyclePhase)
        }
        .padding(.vertical, 10)
    }
}
