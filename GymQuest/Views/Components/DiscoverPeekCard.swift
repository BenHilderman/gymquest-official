// DiscoverPeekCard — design v4.3 Item 1 locked spec.
// Single small "later, if you have time" card at the bottom of Home.
// Refreshes once per day (not per open) — keeps Home's "fast and done"
// identity intact while offering an escape hatch into Discover.

import SwiftUI

struct DiscoverPeekCard: View {
    let title: String?           // e.g. "trending push day · 47 ppl tried"
    let thumbnailURL: URL?
    var onTap: () -> Void = {}

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Tiny thumbnail / placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(GQGradients.primary.opacity(0.10))
                        .frame(width: 44, height: 44)
                    if let url = thumbnailURL {
                        AsyncImage(url: url) { phase in
                            (phase.image ?? Image(systemName: "play.rectangle.fill"))
                                .resizable()
                                .scaledToFill()
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(GQGradients.primary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("later, if you have time")
                        .font(.system(size: 10, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundColor(GQColors.textTertiary)
                    Text(title ?? "trending in your gym")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(GQColors.textPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(GQColors.overlayLight)
        )
    }
}
