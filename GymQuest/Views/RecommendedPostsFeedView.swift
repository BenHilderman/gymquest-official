import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Today's Mix sequence player — fed by the rail's hero picks. Seeded
/// to whichever pick the user tapped so they land on it and can swipe
/// through the rest without losing context. Each card seen is recorded
/// in TodaysMixWatchedStore, the running counter "k of N" sits in the
/// nav bar, and an end-of-mix CTA after the last card closes the loop
/// with "you watched X / N — discover more" + countdown to tomorrow's
/// reset.
struct RecommendedPostsFeedView: View {
    let profile: UserProfile
    let posts: [Post]
    let initialPostId: UUID

    @Environment(\.dismiss) private var dismiss

    /// Updated as each PostCardV2 appears so the nav-bar counter
    /// reflects the user's place in the mix in real time.
    @State private var visibleIndex: Int = 0
    /// Watched count (post ids opened today) — refreshed on appear and
    /// when individual cards report appearing for the first time so
    /// the end-of-mix card can show "X of N".
    @State private var watchedCount: Int = 0
    /// Refreshed every minute by the same publisher used on the rail
    /// so the end-of-mix card's reset countdown stays accurate without
    /// the user re-opening the view.
    @State private var resetLabel: String = TodaysMixWatchedStore.resetCountdown()
    private let countdownTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var totalCount: Int { posts.count }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(posts.enumerated()), id: \.element.id) { idx, post in
                        PostCardV2(
                            post: post,
                            currentUserId: profile.id,
                            currentUserName: profile.name,
                            profile: profile,
                            audioScope: .discover
                        )
                        .id(post.id)
                        .onAppear {
                            visibleIndex = idx
                            TodaysMixWatchedStore.markWatched(post.id)
                            watchedCount = TodaysMixWatchedStore.watchedToday().count
                        }

                        Rectangle()
                            .fill(GQColors.borderSubtle)
                            .frame(height: 1)
                    }

                    endOfMixCard
                        .padding(.top, 24)
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 100)
            }
            .scrollContentBackground(.hidden)
            .gqPageBackground()
            .onAppear {
                watchedCount = TodaysMixWatchedStore.watchedToday().count
                resetLabel = TodaysMixWatchedStore.resetCountdown()
                // One-tick delay so LazyVStack lays out the target before
                // we scroll — otherwise the jump can land off-anchor.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.none) {
                        proxy.scrollTo(initialPostId, anchor: .top)
                    }
                }
            }
            .onReceive(countdownTimer) { _ in
                resetLabel = TodaysMixWatchedStore.resetCountdown()
            }
        }
        .navigationTitle("Today's Mix")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(GQColors.background, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                counterPill
            }
        }
        .instagramBack()
    }

    // MARK: - Counter Pill

    /// `1 / 7` indicator in the trailing nav bar slot. Updates as the
    /// user scrolls because each card's `.onAppear` bumps visibleIndex.
    private var counterPill: some View {
        Text("\(visibleIndex + 1) / \(totalCount)")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(GQColors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(GQColors.surfaceBase)
            )
            .overlay(
                Capsule().stroke(GQColors.borderDefault.opacity(0.6), lineWidth: 0.5)
            )
    }

    // MARK: - End-of-Mix Card

    /// Closes the daily-ritual loop after the user reaches the bottom
    /// of the picks. Shows X-of-N completion, a CTA back into the main
    /// Discover surface, and the reset countdown so the user knows
    /// when a fresh mix unlocks.
    @ViewBuilder
    private var endOfMixCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(GQGradients.primary)

            Text("You watched \(watchedCount) of \(totalCount)")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(GQColors.textPrimary)
                .multilineTextAlignment(.center)

            Text("Tomorrow's mix unlocks soon · \(resetLabel)")
                .font(.system(size: 13))
                .foregroundColor(GQColors.textTertiary)
                .multilineTextAlignment(.center)

            Button {
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                #endif
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Discover more")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Capsule().fill(GQGradients.primary))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(GQColors.surfaceBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(GQColors.borderDefault.opacity(0.6), lineWidth: 0.5)
        )
    }
}
