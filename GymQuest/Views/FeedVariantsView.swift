import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Feed-header variants playground. Each tab applies one small style tweak
/// to the same mocked friends strip + hero card + discover header so you
/// can compare and pick which feel better before promoting one back into
/// the real ExploreView.
///
/// Not wired into production navigation by default — enter via the flask
/// button in the Feed's pinned header (long-press).
struct FeedVariantsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var variant: FeedVariant = .v1Original

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                variantPicker
                Divider().overlay(GQColors.adaptiveOverlay(0.06))

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        variantBlurb
                        variantBody
                    }
                    .padding(.bottom, 40)
                }
            }
            .background(GQColors.background.ignoresSafeArea())
            .navigationTitle("Feed variants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Variant picker

    private var variantPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FeedVariant.allCases) { v in
                    variantChip(v)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func variantChip(_ v: FeedVariant) -> some View {
        let isSelected = variant == v
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { variant = v }
        } label: {
            Text(v.shortLabel)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundColor(isSelected ? .white : GQColors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(chipBackground(isSelected: isSelected))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func chipBackground(isSelected: Bool) -> some View {
        Group {
            if isSelected {
                GQGradients.primary
            } else {
                GQColors.adaptiveOverlay(0.05)
            }
        }
    }

    private var variantBlurb: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(variant.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(GQColors.textPrimary)
            Text(variant.blurb)
                .font(.system(size: 12))
                .foregroundColor(GQColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GQColors.adaptiveOverlay(0.03))
    }

    // MARK: - Variant bodies

    @ViewBuilder
    private var variantBody: some View {
        switch variant {
        case .v1Original:       v1Original
        case .v2NoFriends:      v2NoFriends
        case .v3BigTabs:        v3BigTabs
        case .v4TinyHero:       v4TinyHero
        case .v5MinimalHero:    v5MinimalHero
        case .v6OverflowCount:  v6OverflowCount
        case .v7BoldDiscover:   v7BoldDiscover
        case .v8ChipCounts:     v8ChipCounts
        case .v9FlatHero:       v9FlatHero
        case .v10Blended:       v10Blended
        }
    }

    // MARK: - Shared mock data

    private let mockFriends: [MockFriend] = [
        .init(name: "Marcus", type: "Push", time: "27m", live: true),
        .init(name: "Jake",   type: "Pull", time: "29m", live: true),
        .init(name: "Olivia", type: "Legs", time: "27m", live: true),
        .init(name: "Tyler",  type: "Push", time: "7h",  live: false),
        .init(name: "Emma",   type: "Push", time: "12h", live: false),
        .init(name: "Kai",    type: "Legs", time: "10h", live: false),
        .init(name: "Zoe",    type: "Push", time: "1d",  live: false),
        .init(name: "Priya",  type: "Pull", time: "2d",  live: false),
    ]

    private let chips = ["For You", "Following", "Push", "Pull", "Legs", "Cardio", "Videos"]

    // MARK: - Variant 1: Original (as shipped)

    private var v1Original: some View {
        VStack(alignment: .leading, spacing: 16) {
            mockNavTabs()
            Divider().overlay(GQColors.adaptiveOverlay(0.04))
            mockFriendsStrip()
            mockHero(showEyebrow: true, shadow: true)
            mockDiscoverHeader()
        }
        .padding(.top, 8)
    }

    // MARK: - Variant 2: No friends strip

    private var v2NoFriends: some View {
        VStack(alignment: .leading, spacing: 16) {
            mockNavTabs()
            Divider().overlay(GQColors.adaptiveOverlay(0.04))
            mockHero(showEyebrow: true, shadow: true)
            mockDiscoverHeader()
        }
        .padding(.top, 8)
    }

    // MARK: - Variant 3: Segmented tabs

    private var v3BigTabs: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("", selection: .constant(0)) {
                Text("Friends").tag(0)
                Text("Shorts").tag(1)
                Text("Clubs").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            mockFriendsStrip()
            mockHero(showEyebrow: true, shadow: true)
            mockDiscoverHeader()
        }
        .padding(.top, 8)
    }

    // MARK: - Variant 4: Tiny hero

    private var v4TinyHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            mockNavTabs()
            Divider().overlay(GQColors.adaptiveOverlay(0.04))
            mockFriendsStrip()
            mockTinyHero()
            mockDiscoverHeader()
        }
        .padding(.top, 8)
    }

    // MARK: - Variant 5: Minimal hero (no eyebrow)

    private var v5MinimalHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            mockNavTabs()
            Divider().overlay(GQColors.adaptiveOverlay(0.04))
            mockFriendsStrip()
            mockHero(showEyebrow: false, shadow: true)
            mockDiscoverHeader()
        }
        .padding(.top, 8)
    }

    // MARK: - Variant 6: Overflow count pill

    private var v6OverflowCount: some View {
        VStack(alignment: .leading, spacing: 16) {
            mockNavTabs()
            Divider().overlay(GQColors.adaptiveOverlay(0.04))
            mockFriendsStripWithOverflow()
            mockHero(showEyebrow: true, shadow: true)
            mockDiscoverHeader()
        }
        .padding(.top, 8)
    }

    // MARK: - Variant 7: Bold Discover section header

    private var v7BoldDiscover: some View {
        VStack(alignment: .leading, spacing: 16) {
            mockNavTabs()
            Divider().overlay(GQColors.adaptiveOverlay(0.04))
            mockFriendsStrip()
            mockHero(showEyebrow: true, shadow: true)
            mockBoldDiscoverHeader()
        }
        .padding(.top, 8)
    }

    // MARK: - Variant 8: Chip counts

    private var v8ChipCounts: some View {
        VStack(alignment: .leading, spacing: 16) {
            mockNavTabs()
            Divider().overlay(GQColors.adaptiveOverlay(0.04))
            mockFriendsStrip()
            mockHero(showEyebrow: true, shadow: true)
            mockDiscoverHeaderWithCounts()
        }
        .padding(.top, 8)
    }

    // MARK: - Variant 9: Flat hero (no shadow, matches discover grid)

    private var v9FlatHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            mockNavTabs()
            Divider().overlay(GQColors.adaptiveOverlay(0.04))
            mockFriendsStrip()
            mockHero(showEyebrow: true, shadow: false)
            mockDiscoverHeader()
        }
        .padding(.top, 8)
    }

    // MARK: - Variant 10: Blended (friends inline as discover row 0)

    private var v10Blended: some View {
        VStack(alignment: .leading, spacing: 16) {
            mockNavTabs()
            Divider().overlay(GQColors.adaptiveOverlay(0.04))
            mockHero(showEyebrow: true, shadow: true)
            mockBlendedFriendsRow()
            mockDiscoverHeader()
        }
        .padding(.top, 8)
    }

    // MARK: - Shared mock components

    private func mockNavTabs() -> some View {
        HStack(spacing: 20) {
            Spacer()
            Text("Friends")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GQGradients.primary)
            Text("Shorts")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(GQColors.textTertiary)
            Text("Clubs")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(GQColors.textTertiary)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(GQColors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func mockFriendsStrip() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(mockFriends) { f in
                    friendCell(f)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .mask(fadeMask)
    }

    private func mockFriendsStripWithOverflow() -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(mockFriends.prefix(5)) { f in
                    friendCell(f)
                }
                // Overflow pill
                VStack(spacing: 3) {
                    ZStack {
                        Circle().fill(GQColors.adaptiveOverlay(0.08))
                            .frame(width: 36, height: 36)
                        Text("+12")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(GQColors.textSecondary)
                    }
                    .frame(width: 42, height: 42)

                    Text("More")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                    Text("friends")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(GQColors.textTertiary)
                }
                .frame(width: 54)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func friendCell(_ f: MockFriend) -> some View {
        VStack(spacing: 3) {
            ZStack {
                if f.live {
                    Circle().stroke(GQColors.success, lineWidth: 1.5)
                        .frame(width: 42, height: 42)
                }
                Circle().fill(GQGradients.primary)
                    .frame(width: 36, height: 36)
                Text(String(f.name.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                if f.live {
                    Circle().fill(GQColors.success)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(GQColors.background, lineWidth: 1.5))
                        .frame(width: 42, height: 42, alignment: .bottomTrailing)
                }
            }
            .frame(width: 42, height: 42)

            Text(f.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(GQColors.textPrimary)
                .lineLimit(1)
            Text("\(f.type) · \(f.time)")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(GQColors.textTertiary)
                .lineLimit(1)
        }
        .frame(width: 54)
    }

    private var fadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 0.94),
                .init(color: .black.opacity(0.0), location: 1.0)
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private func mockHero(showEyebrow: Bool, shadow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Gradient top bar like the real hero
            GQGradients.primary.frame(height: 3)
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12).fill(GQColors.adaptiveOverlay(0.1))
                    .frame(width: 72, height: 72)
                    .overlay(Image(systemName: "play.fill")
                        .font(.system(size: 18))
                        .foregroundColor(GQColors.textSecondary))
                VStack(alignment: .leading, spacing: 4) {
                    if showEyebrow {
                        Text("TONIGHT'S PICK")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(GQColors.textTertiary)
                            .tracking(0.5)
                    }
                    Text("Quad Dominant Leg Day")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(GQColors.textPrimary)
                    HStack(spacing: 8) {
                        Text("@jakereeves")
                            .font(.system(size: 11))
                            .foregroundColor(GQColors.textTertiary)
                        Text("Legs · 60 min")
                            .font(.system(size: 11))
                            .foregroundColor(GQColors.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(14)

            HStack {
                Text("+17 did this")
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
                Spacer()
                Text("Start ▸")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(GQGradients.primary.opacity(0.12)))
            }
            .padding(.horizontal, 14).padding(.bottom, 12)
        }
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.white)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: shadow ? .black.opacity(0.08) : .clear, radius: 6, y: 2)
        .padding(.horizontal, 16)
    }

    private func mockTinyHero() -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10).fill(GQGradients.primary.opacity(0.18))
                .frame(width: 48, height: 48)
                .overlay(Image(systemName: "play.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(GQGradients.primary))
            VStack(alignment: .leading, spacing: 2) {
                Text("Quad Dominant Leg Day")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                Text("Tonight · Legs · 60 min · +17 did this")
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text("Start")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(GQGradients.primary))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .padding(.horizontal, 16)
    }

    private func mockDiscoverHeader() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(GQGradients.primary)
                Text("Discover")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            chipRow(chips.map { ($0, nil) })
        }
    }

    private func mockBoldDiscoverHeader() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Discover")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(GQColors.textPrimary)
                Spacer()
                Text("See all")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(GQGradients.primary)
            }
            .padding(.horizontal, 16)
            chipRow(chips.map { ($0, nil) })
        }
    }

    private func mockDiscoverHeaderWithCounts() -> some View {
        let counts = [82, 14, 23, 18, 12, 9, 31]
        let withCounts: [(String, Int?)] = zip(chips, counts).map { ($0.0, $0.1) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(GQGradients.primary)
                Text("Discover")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            chipRow(withCounts)
        }
    }

    private func chipRow(_ items: [(String, Int?)]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    let isSelected = idx == 0
                    HStack(spacing: 4) {
                        Text(item.0)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        if let c = item.1 {
                            Text("\(c)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(isSelected ? .white.opacity(0.8) : GQColors.textTertiary)
                        }
                    }
                    .foregroundColor(isSelected ? .white : GQColors.textSecondary)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(
                        isSelected
                            ? AnyShapeStyle(GQGradients.primary)
                            : AnyShapeStyle(GQColors.adaptiveOverlay(0.05))
                    )
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func mockBlendedFriendsRow() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("TRAINING NOW")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
                    .tracking(0.5)
                Spacer()
                Text("3 friends").font(.system(size: 10))
                    .foregroundColor(GQColors.textTertiary)
            }
            .padding(.horizontal, 16)

            mockFriendsStrip()
        }
    }
}

// MARK: - Variant enum

enum FeedVariant: Int, CaseIterable, Identifiable {
    case v1Original, v2NoFriends, v3BigTabs, v4TinyHero, v5MinimalHero,
         v6OverflowCount, v7BoldDiscover, v8ChipCounts, v9FlatHero, v10Blended

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .v1Original:       return "1. Original"
        case .v2NoFriends:      return "2. No strip"
        case .v3BigTabs:        return "3. Segmented"
        case .v4TinyHero:       return "4. Tiny hero"
        case .v5MinimalHero:    return "5. No eyebrow"
        case .v6OverflowCount:  return "6. +N pill"
        case .v7BoldDiscover:   return "7. Bold header"
        case .v8ChipCounts:     return "8. Chip counts"
        case .v9FlatHero:       return "9. Flat hero"
        case .v10Blended:       return "10. Blended"
        }
    }

    var title: String {
        switch self {
        case .v1Original:       return "Original — as currently shipped"
        case .v2NoFriends:      return "Drop the friends strip"
        case .v3BigTabs:        return "Segmented Friends/Shorts/Clubs"
        case .v4TinyHero:       return "Compact hero, not a full card"
        case .v5MinimalHero:    return "Minimal hero — no eyebrow"
        case .v6OverflowCount:  return "+N more friends pill"
        case .v7BoldDiscover:   return "Bold Discover section header"
        case .v8ChipCounts:     return "Filter chip counts"
        case .v9FlatHero:       return "Flat hero (no shadow)"
        case .v10Blended:       return "Friends inside Discover as row 0"
        }
    }

    var blurb: String {
        switch self {
        case .v1Original:       return "What's on the Feed today — reference baseline."
        case .v2NoFriends:      return "Removes the 'purple stripe' of avatars before the hero. Hero gets more attention; friends reach via the nav tab."
        case .v3BigTabs:        return "SwiftUI .segmented picker instead of 3 text links. Clearer that Friends is one of three pages, not a title."
        case .v4TinyHero:       return "Hero becomes a single-row compact card — leaves more room above the fold for the Discover grid."
        case .v5MinimalHero:    return "Drops the 'TONIGHT'S PICK' eyebrow — the bold title carries enough weight on its own."
        case .v6OverflowCount:  return "Shows first 5 friends + a '+12 More friends' circle. Answers 'how many more are behind the fade'."
        case .v7BoldDiscover:   return "Section header becomes a 26pt bold title with a trailing 'See all' link — matches iOS App Store section aesthetic."
        case .v8ChipCounts:     return "Each filter chip shows how many posts match (Push 23, Pull 18). Feels like a real filter, not decoration."
        case .v9FlatHero:       return "Removes the soft shadow under the hero card so it matches the flat Discover grid. One consistent depth language."
        case .v10Blended:       return "Friends strip becomes the first row of Discover (labeled 'TRAINING NOW'). One continuous feed, no pre-feed intro."
        }
    }
}

// MARK: - Mock data

private struct MockFriend: Identifiable {
    let id = UUID()
    let name: String
    let type: String
    let time: String
    let live: Bool
}

#Preview {
    FeedVariantsView()
}
