// ProfileStoryHighlightsRow — design v4.3 §5A.
// User-curated 3-5 best moments, pinned manually. Owner-only "fresh" dot
// (Item F locked spec) shows on highlights they haven't viewed in 30+ days.
//
// Resolves the actual Story for each slot so the bubble renders real
// thumbnails (media or text glyph) instead of a placeholder. Tap surfaces
// StoryViewerView with the resolved sequence.

import SwiftUI

struct ProfileStoryHighlightsRow: View {
    let slots: [StoryHighlightSlot]
    let stories: [Story]
    let isOwnProfile: Bool
    var onTapStory: (Story, StoryHighlightSlot) -> Void = { _, _ in }

    /// Pairs a slot with its resolved Story. Stories may have been deleted;
    /// those slots silently drop.
    private var resolvedSlots: [(slot: StoryHighlightSlot, story: Story)] {
        slots
            .sorted { $0.slotIndex < $1.slotIndex }
            .compactMap { slot in
                stories.first { $0.id == slot.storyId }.map { (slot, $0) }
            }
    }

    var body: some View {
        if resolvedSlots.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(resolvedSlots, id: \.slot.compositeKey) { pair in
                        slotButton(slot: pair.slot, story: pair.story)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private func slotButton(slot: StoryHighlightSlot, story: Story) -> some View {
        Button {
            onTapStory(story, slot)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .stroke(GQGradients.primary, lineWidth: 2)
                            .frame(width: 60, height: 60)
                        Circle()
                            .fill(GQColors.surfaceSecondary)
                            .frame(width: 54, height: 54)
                            .overlay(thumbnail(for: story))
                            .clipShape(Circle())
                    }

                    // v4.3 §5A — Item F: fresh dot for owner when not viewed 30+ days.
                    // Owner-only — other-profile views never see it.
                    if isOwnProfile && slot.ownerHasNotViewedRecently {
                        Circle()
                            .fill(GQColors.vividPurple)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(GQColors.surfaceBase, lineWidth: 1.5))
                            .offset(x: -2, y: 2)
                    }
                }
                Text(slotLabel(slot: slot, story: story))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(GQColors.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func thumbnail(for story: Story) -> some View {
        if let urlString = story.mediaURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholderThumbnail(for: story)
                }
            }
            .frame(width: 54, height: 54)
        } else {
            placeholderThumbnail(for: story)
        }
    }

    @ViewBuilder
    private func placeholderThumbnail(for story: Story) -> some View {
        switch story.kind {
        case .text:
            Text(String((story.textBody ?? "·").prefix(1)).uppercased())
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(GQGradients.primary)
        case .workoutShare:
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 18))
                .foregroundStyle(GQGradients.primary)
        case .video:
            Image(systemName: "play.fill")
                .font(.system(size: 16))
                .foregroundStyle(GQGradients.primary)
        case .photo:
            Image(systemName: "sparkles")
                .font(.system(size: 18))
                .foregroundStyle(GQGradients.primary)
        }
    }

    private func slotLabel(slot: StoryHighlightSlot, story: Story) -> String {
        if let title = slot.title, !title.isEmpty {
            return title.lowercased()
        }
        // Fall back to a label derived from the story kind / date.
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: story.postedAt).lowercased()
    }
}
