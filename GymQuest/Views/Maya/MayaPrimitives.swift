// MayaPrimitives — reusable subviews shared across the Maya MVP
// screens. Kept in one file so the MVP's visual vocabulary is easy to
// audit in a single read.

import SwiftUI

// MARK: - Maya avatar

/// Circular "M" avatar with the Maya gradient. Four size variants so
/// the same primitive renders cleanly in chip-context, body text, card
/// header, and hero contexts.
struct MayaAvatar: View {
    enum Size {
        case xs, sm, md, lg
        var diameter: CGFloat {
            switch self {
            case .xs: return 16
            case .sm: return 20
            case .md: return 22
            case .lg: return 24
            }
        }
        var fontSize: CGFloat {
            switch self {
            case .xs: return 9
            case .sm: return 11
            case .md: return 11.5
            case .lg: return 12.5
            }
        }
    }

    let size: Size

    init(_ size: Size = .md) { self.size = size }

    var body: some View {
        Text("M")
            .font(.system(size: size.fontSize, weight: .heavy))
            .foregroundColor(.white)
            .frame(width: size.diameter, height: size.diameter)
            .background(
                Circle().fill(MayaTokens.mayaAvatar)
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.24), lineWidth: 0.5)
                    .blendMode(.overlay)
            )
            .shadow(color: MayaTokens.mayaAvatarEnd.opacity(0.2), radius: 2, y: 2)
    }
}

// MARK: - Replay eyebrow chip

/// "⟲ replay" pill used on the Cold Start card. Small violet-tinted
/// rounded chip with a soft brand-gradient backdrop.
struct ReplayEyebrow: View {
    var body: some View {
        HStack(spacing: 5) {
            Text("⟲")
                .font(.system(size: 11, weight: .bold))
            Text("REPLAY")
                .font(.system(size: 9.5, weight: .heavy))
                .tracking(1.3)
        }
        .foregroundColor(MayaTokens.violet)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [
                        MayaTokens.violet.opacity(0.12),
                        MayaTokens.pink.opacity(0.07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        )
        .overlay(
            Capsule().stroke(MayaTokens.violet.opacity(0.26), lineWidth: 1)
        )
    }
}

// MARK: - Beginner-safe hint chip

/// Small soft-green pill rendered on the Cold Start card under the
/// cue preview. Variable label so each chip-type can supply its own
/// short identity string (e.g. "good first lift", "upper body").
struct BeginnerHintChip: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .heavy))
            .foregroundColor(MayaTokens.beg)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(MayaTokens.beg.opacity(0.10))
            )
            .overlay(
                Capsule().stroke(MayaTokens.beg.opacity(0.26), lineWidth: 1)
            )
    }
}

// MARK: - Maya identity line ("Maya · guided replay")

/// Two-line vertical identity block: name + small uppercase subline.
/// Shown on the Cold Start replay card.
struct MayaIdentityLine: View {
    var avatarSize: MayaAvatar.Size = .lg
    var nameSize: CGFloat = 14
    var sublineSize: CGFloat = 9.5

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            MayaAvatar(avatarSize)
            VStack(alignment: .leading, spacing: 3) {
                Text("Maya")
                    .font(.system(size: nameSize, weight: .heavy))
                    .foregroundColor(MayaTokens.text)
                Text("GUIDED REPLAY")
                    .font(.system(size: sublineSize, weight: .heavy))
                    .tracking(0.6)
                    .foregroundColor(MayaTokens.muted)
            }
        }
    }
}

// MARK: - Cue card

/// "maya's form cue" — small attribution-labeled cue card. Standard
/// variant is soft violet wash; `.finalSet` variant gets a stronger
/// gradient for the last-set state.
struct CueCard: View {
    enum Variant {
        case preview      // Cold Start card — smaller padding
        case standard     // Active Replay non-final set
        case finalSet     // Active Replay final set — stronger gradient
    }

    let variant: Variant
    let label: String
    let body_: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                MayaAvatar(.xs)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.3)
                    .foregroundColor(headlineColor)
            }
            Text(body_)
                .font(.system(size: bodyFontSize, weight: .bold))
                .foregroundColor(MayaTokens.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, variant == .preview ? 11 : 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(backgroundGradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var bodyFontSize: CGFloat {
        switch variant {
        case .preview: return 12.5
        case .standard, .finalSet: return 13.5
        }
    }

    private var headlineColor: Color {
        variant == .finalSet ? MayaTokens.violet : Color(red: 0x75 / 255, green: 0x58 / 255, blue: 0xA8 / 255)
    }

    private var backgroundGradient: LinearGradient {
        switch variant {
        case .preview, .standard:
            return LinearGradient(
                colors: [
                    MayaTokens.mayaAvatarStart.opacity(0.07),
                    MayaTokens.mayaAvatarEnd.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .finalSet:
            return LinearGradient(
                colors: [
                    MayaTokens.violet.opacity(0.08),
                    MayaTokens.pink.opacity(0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var borderColor: Color {
        variant == .finalSet
            ? MayaTokens.violet.opacity(0.32)
            : MayaTokens.mayaAvatarEnd.opacity(0.22)
    }
}

// MARK: - Privacy summary pill

/// "🔒 private by default · no strangers · you choose what friends
/// see" — the Cold Start trust footer.
struct PrivacySummaryPill: View {
    var body: some View {
        HStack(spacing: 5) {
            Text("🔒").font(.system(size: 11))
            Text("private by default · no strangers · you choose what friends see")
                .font(.system(size: 10.5, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundColor(MayaTokens.muted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MayaTokens.text.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MayaTokens.border, lineWidth: 1)
        )
    }
}

// MARK: - Social bridge line

/// "🌿 Maya helps solo days · friends can leave real replays too"
/// — soft-green bottom line on Cold Start.
struct SocialBridgeLine: View {
    let message: String

    init(_ message: String = "Maya helps solo days · friends can leave real replays too") {
        self.message = message
    }

    var body: some View {
        HStack(spacing: 5) {
            Text("🌿").font(.system(size: 11))
            Text(message)
                .font(.system(size: 10.5, weight: .heavy))
                .foregroundColor(MayaTokens.beg)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(MayaTokens.beg.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MayaTokens.beg.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Primary brand CTA

/// 54pt-tall pill button with the brand gradient. Used for "Start
/// Replay" and "Save Win". Pass `.warm` for the Run It Back variant.
struct MayaPrimaryButtonStyle: ButtonStyle {
    enum Tone { case brand, warm }

    let tone: Tone

    init(tone: Tone = .brand) { self.tone = tone }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .heavy))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                Capsule().fill(tone == .brand ? MayaTokens.brand : MayaTokens.warm)
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.24), lineWidth: 0.5)
                    .blendMode(.overlay)
            )
            .shadow(color: MayaTokens.violet.opacity(0.28), radius: 14, y: 4)
            .shadow(color: MayaTokens.pink.opacity(0.18), radius: 24, y: 12)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Secondary 46pt pill — white fill, hairline border.
struct MayaSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .bold))
            .foregroundColor(MayaTokens.text)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                Capsule().fill(MayaTokens.card)
            )
            .overlay(
                Capsule().stroke(MayaTokens.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Tertiary 38pt text-only button — for "Not now" / "skip · adjust
/// weight" surfaces.
struct MayaTertiaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(MayaTokens.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Selection chip ("pick today's replay" row)

/// Pill chip with a clear selected / unselected state. The selected
/// state uses a brand-gradient backdrop + violet border + 800 weight
/// per the locked v3 hierarchy patch.
struct MayaChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isSelected ? .heavy : .bold))
                .foregroundColor(isSelected ? MayaTokens.violet : MayaTokens.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(
                        isSelected
                            ? AnyShapeStyle(selectedFill)
                            : AnyShapeStyle(MayaTokens.card)
                    )
                )
                .overlay(
                    Capsule().stroke(
                        isSelected ? MayaTokens.violet.opacity(0.42) : MayaTokens.border,
                        lineWidth: 1
                    )
                )
                .shadow(
                    color: isSelected
                        ? MayaTokens.violet.opacity(0.14)
                        : Color.black.opacity(0.04),
                    radius: isSelected ? 8 : 2,
                    y: isSelected ? 2 : 1
                )
        }
        .buttonStyle(.plain)
    }

    private var selectedFill: LinearGradient {
        LinearGradient(
            colors: [
                MayaTokens.violet.opacity(0.14),
                MayaTokens.mayaAvatarEnd.opacity(0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Phone-status header pieces

/// Italic CoLift wordmark with the brand gradient — top of Cold Start.
struct CoLiftWordmark: View {
    var body: some View {
        Text("CoLift")
            .font(.system(size: 22, weight: .heavy))
            .italic()
            .tracking(-0.5)
            .foregroundStyle(MayaTokens.brand)
    }
}

// MARK: - Demo silhouette (simple exercise placeholder)

/// Calm warm container with a simple equipment silhouette. Used in
/// Active Replay's "now lifting" card. Pulses a subtle violet motion
/// bar at the bottom when `motion` is true.
struct ExerciseDemoTile: View {
    let exerciseName: String
    let hint: String
    var motion: Bool = true

    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 11) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 54, height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MayaTokens.border, lineWidth: 1)
                    )

                // Generic dumbbell glyph — same primitive across all
                // exercise rows for v1. Real per-exercise art is in
                // the deferred manifest.
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 22))
                    .foregroundColor(MayaTokens.soft)
                    .frame(width: 54, height: 42)

                if motion {
                    Capsule()
                        .fill(MayaTokens.violet)
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                        .scaleEffect(x: pulse ? 1.0 : 0.6, y: 1.0, anchor: .center)
                        .opacity(pulse ? 0.9 : 0.3)
                        .offset(y: 1)
                }
            }
            .onAppear {
                guard motion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("DEMO")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1.1)
                    .foregroundColor(MayaTokens.muted)
                Text(exerciseName.lowercased())
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(MayaTokens.text)
                Text(hint)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(MayaTokens.soft)
            }
            Spacer(minLength: 0)
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0xFB / 255, green: 0xF9 / 255, blue: 0xFC / 255))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MayaTokens.border, lineWidth: 1)
        )
    }
}
