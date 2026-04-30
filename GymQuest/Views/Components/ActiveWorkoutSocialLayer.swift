// Active Workout social layer + transformed rest timer + finish moment.
// Design v4.3 §7A.

import SwiftUI

/// Tiny reaction bubble that auto-dismisses after 4 sec, with haptic on appear.
struct ReactionBubbleAutoDismiss: View {
    let emoji: String
    let fromName: String
    @State private var visible = true

    var body: some View {
        HStack(spacing: 6) {
            Text(emoji).font(.system(size: 18))
            Text(fromName.lowercased()).font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(.white.opacity(0.18)))
        .foregroundStyle(.white)
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.7)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: visible)
        .onAppear {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                visible = false
            }
        }
    }
}

/// "X friends hyped you" pill at bottom — tap to expand reaction inbox.
struct FriendsHypedPill: View {
    let count: Int
    var onTap: () -> Void = {}
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").font(.caption)
                Text("\(count) friends hyped you").font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Capsule().fill(LinearGradient(colors: [.orange, .red],
                                                         startPoint: .leading,
                                                         endPoint: .trailing)))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

/// "X watching" pill in the workout header.
struct XWatchingPill: View {
    let count: Int
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "eye.fill").font(.caption2)
            Text("\(count) watching").font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(0.18)))
        .foregroundStyle(.white)
    }
}

/// Privacy/ghost toggle in the workout header.
struct WorkoutGhostToggle: View {
    @Binding var level: GhostModeLevel
    var body: some View {
        Menu {
            ForEach(GhostModeLevel.allCases) { l in
                Button(l.label) { level = l }
            }
        } label: {
            Image(systemName: level == .ghost ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 12, weight: .semibold))
                .padding(8)
                .background(Circle().fill(.white.opacity(0.10)))
                .foregroundStyle(.white)
        }
    }
}

/// Rest timer transformed: friend reaction inbox / peer signal / Watch clip / music controls.
struct RestTimerTransformed: View {
    let restSeconds: Int
    let recentReactionEmoji: String?
    let recentReactionFrom: String?
    let peerSignal: String?
    var onSkipClip: () -> Void = {}
    var onPlayPauseMusic: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("rest")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatRest(restSeconds))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
            }

            if let emoji = recentReactionEmoji, let from = recentReactionFrom {
                ReactionBubbleAutoDismiss(emoji: emoji, fromName: from)
            }

            if let peer = peerSignal {
                Text(peer)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: onPlayPauseMusic) {
                    Image(systemName: "playpause.fill").padding(8)
                        .background(Circle().fill(.white.opacity(0.10)))
                }
                Button(action: onSkipClip) {
                    Image(systemName: "forward.fill").padding(8)
                        .background(Circle().fill(.white.opacity(0.10)))
                }
            }
            .foregroundStyle(.white)
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))
    }

    private func formatRest(_ s: Int) -> String {
        let m = s / 60, r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}

/// Finish moment — 3-second pre-proof summary per design §7A.
struct FinishMomentView: View {
    let totalDurationLabel: String
    let totalVolumeLabel: String
    let prCount: Int
    let aboutToSee: Int
    let partnerLine: String?
    @State private var visible = false

    var body: some View {
        VStack(spacing: 14) {
            Text("workout complete")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(totalDurationLabel)
                .font(.system(size: 44, weight: .bold, design: .monospaced))
                .opacity(visible ? 1 : 0).scaleEffect(visible ? 1 : 0.85)

            HStack(spacing: 24) {
                StatColumn(value: totalVolumeLabel, label: "volume")
                StatColumn(value: "\(prCount)", label: "PRs")
            }
            .opacity(visible ? 1 : 0)

            Text("\(aboutToSee) people are about to see this")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .opacity(visible ? 1 : 0)

            if let partnerLine {
                Text(partnerLine)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.white.opacity(0.10)))
                    .opacity(visible ? 1 : 0)
            }
        }
        .padding(28)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.6)))
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                visible = true
            }
        }
    }

    private struct StatColumn: View {
        let value: String
        let label: String
        var body: some View {
            VStack {
                Text(value).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// PR Moment — full-screen 2-sec celebration. Auto-records 3-sec via camera if enabled.
struct PRMomentCelebration: View {
    let displayValue: String   // "225 x 5"
    let unitsLabel: String
    @State private var visible = false
    var onShare: () -> Void = {}
    var onDismiss: () -> Void = {}

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("NEW PR")
                    .font(.system(size: 14, weight: .black))
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Capsule().fill(LinearGradient(colors: [.orange, .pink],
                                                                 startPoint: .leading, endPoint: .trailing)))
                Text(displayValue)
                    .font(.system(size: 64, weight: .black, design: .rounded))
                Text(unitsLabel).font(.title3).foregroundStyle(.secondary)
                Text("🐐").font(.system(size: 64))

                Button("share this PR?", action: onShare)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 12)

                Button("close", action: onDismiss)
                    .foregroundStyle(.secondary)
            }
            .scaleEffect(visible ? 1 : 0.8)
            .opacity(visible ? 1 : 0)
            .foregroundStyle(.white)
        }
        .onAppear {
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                visible = true
            }
        }
    }
}

#if canImport(UIKit)
import UIKit
#endif
