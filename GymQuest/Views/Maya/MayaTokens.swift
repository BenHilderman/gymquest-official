// MayaTokens — design tokens for the Maya MVP build.
//
// Mirrors the locked v3 HTML spec colors + gradients so the native
// app reads identically to the reviewed mockup. Some tokens overlap
// with existing GQColors / GQGradients; we keep these Maya-specific
// so a token tweak to the legacy app doesn't drift the MVP visuals.

import SwiftUI

enum MayaTokens {

    // MARK: - Surface colors

    /// Page background — warm off-white.
    static let bg = Color(red: 0xF7 / 255, green: 0xF5 / 255, blue: 0xF8 / 255)
    /// Card surface.
    static let card = Color.white
    /// Standard border.
    static let border = Color(red: 0xE9 / 255, green: 0xE4 / 255, blue: 0xEC / 255)
    /// Hairline border for inner separations.
    static let hairline = Color(red: 0xF0 / 255, green: 0xEB / 255, blue: 0xF3 / 255)

    // MARK: - Text colors

    /// Primary text (#161418).
    static let text = Color(red: 0x16 / 255, green: 0x14 / 255, blue: 0x18 / 255)
    /// Secondary / soft text.
    static let soft = Color(red: 0x6B / 255, green: 0x68 / 255, blue: 0x73 / 255)
    /// Muted text.
    static let muted = Color(red: 0x9A / 255, green: 0x96 / 255, blue: 0xA3 / 255)

    // MARK: - Brand colors

    static let violet = Color(red: 0x8A / 255, green: 0x5C / 255, blue: 0xFF / 255)
    static let pink = Color(red: 0xF4 / 255, green: 0x5B / 255, blue: 0xB5 / 255)
    static let blue = Color(red: 0x2F / 255, green: 0x8C / 255, blue: 0xFF / 255)

    /// Soft green used for the beginner-safe hint chip + social bridge.
    static let beg = Color(red: 0x3A / 255, green: 0x7A / 255, blue: 0x1F / 255)

    /// Maya avatar gradient end-points (#A189D4 → #876BBE).
    static let mayaAvatarStart = Color(red: 0xA1 / 255, green: 0x89 / 255, blue: 0xD4 / 255)
    static let mayaAvatarEnd = Color(red: 0x87 / 255, green: 0x6B / 255, blue: 0xBE / 255)

    // MARK: - Gradients

    /// Primary brand gradient — blue → violet → pink (135°).
    static let brand = LinearGradient(
        colors: [blue, violet, pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Warm gradient — violet → pink. Used by Run It Back CTA.
    static let warm = LinearGradient(
        colors: [violet, pink],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Maya avatar gradient.
    static let mayaAvatar = LinearGradient(
        colors: [mayaAvatarStart, mayaAvatarEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Card halo — soft radial brand wash behind the Cold Start replay
    /// card. Approximation of the dual-radial CSS via two stacked
    /// radial gradients.
    static let cardHalo = LinearGradient(
        colors: [
            violet.opacity(0.06),
            pink.opacity(0.04),
            Color.clear
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Subtle violet-pink wash for the saved-state card.
    static let savedCard = LinearGradient(
        colors: [violet.opacity(0.08), pink.opacity(0.06)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
