// ReportSheetView — content-safety phase 3B.
//
// Single sheet presented from any content item's overflow menu (Post,
// Comment, DMMessage, SquadMessage, Story, UserProfile). Picks a reason
// + optional 240-char note + submits via ContentReportService.
//
// Idempotent — submitting twice on the same target shows "already reported".

import SwiftUI
import SwiftData

struct ReportSheetView: View {
    /// What's being reported. Caller decides target + reporterId.
    let reporterId: UUID
    let targetKind: ContentReportTargetKind
    let targetId: UUID
    let targetTitle: String  // e.g. "post by @marcus" — shown for confirmation

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedReason: ContentReportReason? = nil
    @State private var note: String = ""
    @State private var showAlreadyReported = false
    @State private var didSubmit = false

    private let noteCharLimit = 240

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(didSubmit ? "thanks" : "report")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("cancel") { dismiss() }
                    }
                    if !didSubmit {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("send") { submit() }
                                .disabled(selectedReason == nil)
                        }
                    } else {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("done") { dismiss() }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            showAlreadyReported = ContentReportService.didReport(
                reporterId: reporterId,
                targetId: targetId,
                in: modelContext
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if showAlreadyReported {
            alreadyReportedState
        } else if didSubmit {
            successState
        } else {
            picker
        }
    }

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(targetTitle.lowercased())
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textTertiary)
                    .padding(.horizontal, 4)

                Text("what's wrong?")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .padding(.horizontal, 4)

                VStack(spacing: 8) {
                    ForEach(ContentReportReason.allCases) { reason in
                        reasonRow(reason)
                    }
                }

                Text("anything else? (optional)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                TextEditor(text: $note)
                    .frame(minHeight: 80, maxHeight: 120)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(GQColors.adaptiveOverlay(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(GQColors.borderDefault, lineWidth: 1)
                    )
                    .onChange(of: note) { _, newValue in
                        if newValue.count > noteCharLimit {
                            note = String(newValue.prefix(noteCharLimit))
                        }
                    }
                Text("\(noteCharLimit - note.count) characters left")
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
    }

    private func reasonRow(_ reason: ContentReportReason) -> some View {
        let isSelected = selectedReason == reason
        return Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            selectedReason = reason
        } label: {
            HStack {
                Text(reason.displayLabel)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : GQColors.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected
                          ? AnyShapeStyle(GQGradients.primary)
                          : AnyShapeStyle(GQColors.adaptiveOverlay(0.06)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.clear : GQColors.borderDefault, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var successState: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(GQGradients.primary)
            Text("reported")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(GQColors.textPrimary)
            Text("our team reviews reports and acts on them quickly. you won't see this content again.")
                .font(.system(size: 14))
                .foregroundColor(GQColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var alreadyReportedState: some View {
        VStack(spacing: 14) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(GQColors.textSecondary)
            Text("already reported")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(GQColors.textPrimary)
            Text("you've already filed a report for this. our team is reviewing it.")
                .font(.system(size: 13))
                .foregroundColor(GQColors.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func submit() {
        guard let reason = selectedReason else { return }
        ContentReportService.report(
            reporterId: reporterId,
            targetKind: targetKind,
            targetId: targetId,
            reason: reason,
            note: note.isEmpty ? nil : note,
            in: modelContext
        )
        withAnimation { didSubmit = true }
    }
}
