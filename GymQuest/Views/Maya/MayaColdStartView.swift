// MayaColdStartView — Screen 1 of the Maya MVP. Renders the locked
// Cold Start hierarchy from the v3 mockup: wordmark → headline →
// subhead → differentiator → replay card → chip row → privacy summary
// → social bridge.
//
// Owns no session state itself; the parent root view holds the
// selected chip and drives Start Replay.

import SwiftUI

struct MayaColdStartView: View {
    @Binding var selectedChip: ReplayChipType
    let onStartReplay: () -> Void

    /// Replay derived from the currently selected chip. Pulled
    /// computed-style so a chip tap updates everything in the card.
    private var selectedReplay: Replay {
        MayaReplayLibrary.replay(for: selectedChip)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                wordmarkRow

                headline
                subhead
                differentiator

                replayCard
                    .padding(.bottom, 8)

                chipsSection

                PrivacySummaryPill()
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                SocialBridgeLine()
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 24)
            }
        }
        .background(MayaTokens.bg.ignoresSafeArea())
        .onAppear {
            ResearchEventLogger.shared.log(.cold_start_viewed, metadata: [
                "replayId": selectedReplay.id.uuidString,
                "replayTitle": selectedReplay.title,
                "chip": selectedChip.rawValue
            ])
        }
    }

    // MARK: - Sections

    private var wordmarkRow: some View {
        CoLiftWordmark()
            .padding(.top, 6)
            .padding(.bottom, 12)
    }

    private var headline: some View {
        Text("Don't lift\nalone.")
            .font(.system(size: 36, weight: .heavy))
            .tracking(-1.2)
            .foregroundColor(MayaTokens.text)
            .multilineTextAlignment(.center)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }

    private var subhead: some View {
        Text("Start with Maya. No invite needed.")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(MayaTokens.soft)
            .multilineTextAlignment(.center)
            .padding(.bottom, 10)
    }

    private var differentiator: some View {
        Text("made for days your friends can't lift with you")
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(MayaTokens.violet)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
    }

    private var replayCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReplayEyebrow()
                .padding(.bottom, 12)

            Text(selectedReplay.title)
                .font(.system(size: 24, weight: .heavy))
                .tracking(-0.6)
                .foregroundColor(MayaTokens.text)
                .padding(.bottom, 5)

            Text(metaText)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(MayaTokens.soft)
                .padding(.bottom, 14)

            MayaIdentityLine()
                .padding(.bottom, 10)

            CueCard(
                variant: .preview,
                label: selectedReplay.cuePreviewLabel,
                body_: selectedReplay.cuePreviewText
            )
            .padding(.bottom, 14)

            HStack(spacing: 5) {
                BeginnerHintChip(label: selectedReplay.tag)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 16)

            Button(action: handleStart) {
                HStack(spacing: 6) {
                    Text("Start Replay")
                    Text("→").font(.system(size: 18, weight: .semibold))
                }
            }
            .buttonStyle(MayaPrimaryButtonStyle())
            .accessibilityLabel("Start Replay")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(MayaTokens.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(MayaTokens.border, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(MayaTokens.cardHalo)
                .allowsHitTesting(false)
        )
        .shadow(color: MayaTokens.violet.opacity(0.07), radius: 28, y: 12)
        .shadow(color: MayaTokens.pink.opacity(0.05), radius: 48, y: 28)
        .padding(.horizontal, 20)
    }

    private var metaText: String {
        let invite = selectedReplay.noInviteNeeded ? "no invite needed" : "invite ready"
        return "\(selectedReplay.durationMinutes) min · \(invite)"
    }

    private var chipsSection: some View {
        VStack(spacing: 0) {
            Text("pick today's replay")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(MayaTokens.soft)
                .padding(.top, 18)
                .padding(.bottom, 10)

            chipRows
        }
    }

    /// Chips render in two flexible rows so we never overflow on
    /// smaller screens. SwiftUI's `Layout` could replace this with a
    /// proper flow layout; the v1 MVP uses a 3+2 split that matches
    /// the v3 mockup at 360pt-wide phones.
    private var chipRows: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                chip(.goodFirstLift)
                chip(.returningAfterBreak)
            }
            HStack(spacing: 7) {
                chip(.upperBody)
                chip(.lowerBody)
                chip(.quickLift)
            }
        }
        .padding(.horizontal, 20)
    }

    private func chip(_ type: ReplayChipType) -> some View {
        MayaChip(
            label: type.label,
            isSelected: selectedChip == type,
            action: { selectChip(type) }
        )
    }

    // MARK: - Actions

    private func selectChip(_ type: ReplayChipType) {
        guard selectedChip != type else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
            selectedChip = type
        }
        ResearchEventLogger.shared.log(.replay_chip_selected, metadata: [
            "chip": type.rawValue,
            "replayId": MayaReplayLibrary.replay(for: type).id.uuidString,
            "replayTitle": MayaReplayLibrary.replay(for: type).title
        ])
    }

    private func handleStart() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        ResearchEventLogger.shared.log(.start_replay_tapped, metadata: [
            "chip": selectedChip.rawValue,
            "replayId": selectedReplay.id.uuidString,
            "replayTitle": selectedReplay.title
        ])
        onStartReplay()
    }
}
