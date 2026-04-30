// CyclePhaseChip — content-psychology pass.
//
// Deeply opt-in cycle phase tracker for users who want it. Lives in
// Profile settings as a discreet chip; tap → small sheet to log
// follicular / ovulation / luteal / period / "skip this." Stored
// locally only (UserProfile.currentCyclePhase, never synced to
// Supabase). Coach service reads it to soften intensity suggestions
// during high-fatigue phases.
//
// Design rules per the brainstorm:
//   - Default off — never assume. User opts in by tapping "track this"
//     once in settings.
//   - On-device only — never written to a synced field.
//   - Honest framing — "your phase, your call" not "log to optimize".
//   - One-tap dismiss — easy to skip / change / clear.

import SwiftUI

struct CyclePhaseChip: View {
    /// Current phase string. Empty = not tracking. Bound so the chip
    /// can both display and persist via the parent's @Bindable
    /// UserProfile.
    @Binding var currentPhase: String
    @State private var showingSheet = false

    var body: some View {
        Button {
            showingSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
                Text(displayLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(GQColors.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(GQColors.adaptiveOverlay(0.06)))
            .overlay(Capsule().stroke(GQColors.borderDefault, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingSheet) {
            CyclePhaseSheet(currentPhase: $currentPhase)
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
    }

    private var displayLabel: String {
        currentPhase.isEmpty ? "phase: skip" : "phase: \(currentPhase)"
    }
}

private struct CyclePhaseSheet: View {
    @Binding var currentPhase: String
    @Environment(\.dismiss) private var dismiss

    private let phases = ["follicular", "ovulation", "luteal", "period"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("phase tracking")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(GQColors.textPrimary)
                Text("your phase, your call. on-device only — never synced anywhere.")
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textSecondary)
            }

            VStack(spacing: 8) {
                ForEach(phases, id: \.self) { phase in
                    phaseRow(phase)
                }
                phaseRow("skip", explicit: true)
            }
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GQColors.surfaceBase)
    }

    private func phaseRow(_ phase: String, explicit: Bool = false) -> some View {
        let isSelected = (explicit && currentPhase.isEmpty) || (!explicit && currentPhase == phase)
        return Button {
            currentPhase = explicit ? "" : phase
            dismiss()
        } label: {
            HStack {
                Text(phase)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isSelected ? .white : GQColors.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(GQGradients.primary)
                          : AnyShapeStyle(GQColors.adaptiveOverlay(0.05)))
            )
        }
        .buttonStyle(.plain)
    }
}
