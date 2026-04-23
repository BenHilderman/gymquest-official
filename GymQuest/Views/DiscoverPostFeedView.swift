import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Scrollable feed of Discover posts rendered with the Friends-tab
/// card (PostCardV2). Seeded to a specific post on open, with the
/// Discover filter chips + Browse/Watch toggle pinned to the top so
/// the user can keep browsing the same ranked pool without bouncing
/// back to the grid.
struct DiscoverPostFeedView: View {
    let profile: UserProfile
    let initialPostId: UUID
    @Binding var discoverFilter: String
    @Binding var discoverMode: DiscoverMode
    let discoverChips: [String]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Post.timestamp, order: .reverse) private var allPosts: [Post]
    @Query(sort: \Workout.date, order: .reverse) private var recentWorkouts: [Workout]
    @Query private var follows: [Friend]

    private var filteredPosts: [Post] {
        let followedIds = Set(follows.filter { $0.userId == profile.id }.map(\.odId))
        var pool = allPosts
        if discoverFilter == "Following" {
            pool = pool.filter { followedIds.contains($0.authorId) || $0.authorId == profile.id }
        }
        let ctx = DiscoverFeedBuilder.Context(
            allPosts: pool,
            profile: profile,
            recentWorkouts: recentWorkouts,
            followedIds: followedIds,
            watchDwell: WatchTimeTracker.shared.dwellByPost,
            nextRecommendation: NextWorkoutService.recommend(profile: profile, recentWorkouts: recentWorkouts)
        )
        let filter: String? = {
            switch discoverFilter {
            case "For You", "Following": return nil
            default: return discoverFilter
            }
        }()
        let items = DiscoverFeedBuilder.build(from: ctx, typeFilter: filter)

        // Mode filter matches ExploreView: Browse = all, Watch = video-only.
        let matched: [DiscoverFeedItem]
        switch discoverMode {
        case .browse: matched = items
        case .watch: matched = items.filter { if case .video = $0 { return true }; return false }
        }

        // Preserve order; strip the suggestion wrapper down to posts only —
        // PostCardV2 only needs Post and knows how to render shared data.
        return matched.map { $0.post }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredPosts) { post in
                        PostCardV2(
                            post: post,
                            currentUserId: profile.id,
                            currentUserName: profile.name,
                            profile: profile,
                            audioScope: .discover
                        )
                        .id(post.id)

                        Rectangle()
                            .fill(GQColors.borderSubtle)
                            .frame(height: 1)
                    }
                }
                .padding(.bottom, 100)
            }
            .scrollContentBackground(.hidden)
            .gqPageBackground()
            .onAppear {
                // One-tick delay so the lazy stack has laid out the target
                // cell before we scroll — jumping on the initial frame
                // sometimes lands on the wrong row.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.none) {
                        proxy.scrollTo(initialPostId, anchor: .top)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            filterStrip
        }
        .navigationTitle("Discover")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(GQColors.background, for: .navigationBar)
        .instagramBack()
    }

    /// Same chip layout Discover uses — the user stays in the same
    /// filter context when they tap a tile; no need to re-learn the UI.
    private var filterStrip: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(discoverChips, id: \.self) { chip in
                        let isSelected = discoverFilter == chip
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                discoverFilter = chip
                            }
                        } label: {
                            Text(chip)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                .foregroundColor(isSelected ? .white : GQColors.textSecondary)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(
                                    isSelected
                                        ? AnyShapeStyle(GQGradients.primary)
                                        : AnyShapeStyle(GQColors.adaptiveOverlay(0.05))
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            modeToggle
                .padding(.trailing, 16)
        }
        .padding(.vertical, 8)
        .background(GQColors.background)
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            ForEach(DiscoverMode.allCases) { mode in
                let selected = discoverMode == mode
                Button {
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    withAnimation(.easeInOut(duration: 0.18)) { discoverMode = mode }
                } label: {
                    Image(systemName: mode.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(selected ? .white : GQColors.textSecondary)
                        .frame(width: 26, height: 22)
                        .background(
                            Group {
                                if selected { GQGradients.primary }
                                else { Color.clear }
                            }
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.label)
            }
        }
        .padding(2)
        .background(GQColors.surfaceBase)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(GQColors.borderDefault, lineWidth: 1))
    }
}
