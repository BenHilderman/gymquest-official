// SplitBackfillStrip — design v4.3 Item D locked spec.
// Always-on secondary strip below the friend live-now row on Home Slot 4.
// "from your gym · training your split now" — clearly labeled, smaller
// avatars, NO presence rings (preserves friend-ring trust signal).

import SwiftUI

struct SplitBackfillItem: Identifiable {
    let id: UUID
    let displayName: String
    let avatarURL: URL?
}

struct SplitBackfillStrip: View {
    let items: [SplitBackfillItem]
    var onTap: (SplitBackfillItem) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("from your gym · training your split now")
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundColor(GQColors.textTertiary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items.prefix(5)) { item in
                        Button { onTap(item) } label: {
                            VStack(spacing: 4) {
                                // No presence ring — visual demotion vs. friend strip
                                ZStack {
                                    Circle()
                                        .fill(GQColors.surfaceSecondary)
                                        .frame(width: 44, height: 44)
                                    if let url = item.avatarURL {
                                        AsyncImage(url: url) { phase in
                                            (phase.image ?? Image(systemName: "person.fill"))
                                                .resizable().scaledToFill()
                                        }
                                        .frame(width: 44, height: 44)
                                        .clipShape(Circle())
                                    } else {
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(GQColors.textTertiary)
                                    }
                                }
                                Text(item.displayName.lowercased())
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(GQColors.textTertiary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 56)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if items.isEmpty {
                        // Empty placeholder so the strip still indicates "people are training"
                        ForEach(0..<3, id: \.self) { _ in
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(GQColors.surfaceSecondary)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(GQColors.textTertiary.opacity(0.4))
                                    )
                                Text("·")
                                    .font(.system(size: 10))
                                    .foregroundColor(GQColors.textTertiary.opacity(0.3))
                                    .frame(maxWidth: 56)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
