import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Scrollable feed of the Tonight's Pick carousel — all 5 ranked hero
/// picks rendered with PostCardV2 (same card as Friends and Discover
/// post feeds). Seeded to whichever pick the user tapped, so they land
/// on the one they were already looking at and can swipe through the
/// rest without bouncing back.
struct RecommendedPostsFeedView: View {
    let profile: UserProfile
    let posts: [Post]
    let initialPostId: UUID

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(posts) { post in
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
                // One-tick delay so LazyVStack lays out the target before
                // we scroll — otherwise the jump can land off-anchor.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.none) {
                        proxy.scrollTo(initialPostId, anchor: .top)
                    }
                }
            }
        }
        .navigationTitle("Tonight's Picks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(GQColors.background, for: .navigationBar)
        .instagramBack()
    }
}
