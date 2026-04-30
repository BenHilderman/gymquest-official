// RateLimitToast — content-safety phase 4D.
//
// Slim auto-dismissing toast for soft rate-limits. Renders 12pt above
// the home tab bar, never covers content. "you're posting fast — try
// again in 4 min" style. Hard caps render the full sheet variant
// (RateLimitHardCapSheet) so the user sees the explicit "try tomorrow"
// framing.

import SwiftUI

struct RateLimitToast: View {
    /// Reason — typically "you're posting fast" or action-specific.
    let title: String
    /// Time until the next try opens up.
    let retryAfter: TimeInterval

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GQGradients.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Text("try again in \(formattedRetry)")
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(GQColors.surfaceSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(GQColors.borderDefault, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }

    private var formattedRetry: String {
        if retryAfter < 60 { return "a moment" }
        let minutes = Int(retryAfter / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = max(1, minutes / 60)
        return hours == 1 ? "an hour" : "\(hours) hours"
    }
}

/// Hard-cap variant — full-width sheet for daily limits hit. More
/// explicit framing because hitting the daily cap is rare for normal
/// users and the messaging needs to make sense to them.
struct RateLimitHardCapSheet: View {
    let title: String
    let body_: String
    let retryAfter: TimeInterval
    var onDismiss: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 38))
                .foregroundStyle(GQGradients.primary)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(GQColors.textPrimary)
                .multilineTextAlignment(.center)
            Text(body_)
                .font(.system(size: 14))
                .foregroundColor(GQColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text(retryFraming)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(GQColors.textTertiary)
            Button("got it") { onDismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(GQColors.surfaceBase)
    }

    private var retryFraming: String {
        if retryAfter < 3600 { return "try again soon" }
        let hours = Int(retryAfter / 3600)
        if hours < 24 { return "try again in \(hours)h" }
        return "try again tomorrow"
    }
}
