// Story Viewer — design v4.3 §3C viewing.
// Vertical full-screen, swipe between, tap right next, tap left previous,
// hold pause, swipe up reply (sends to DM), react quick emoji, view count for poster.

import SwiftUI

struct StoryViewerView: View {
    /// Mutable so the caught-up overlay can swap in public stories without
    /// dismissing/re-presenting the viewer (locked spec §2 — caught-up
    /// transition flows into "from your gym / trending").
    @State var stories: [Story]
    @State private var index: Int
    @State private var paused: Bool = false
    @State private var elapsed: Double = 0
    @Environment(\.dismiss) private var dismiss
    var onReply: (Story, String) -> Void = { _, _ in }
    var onReact: (Story, LiftReaction) -> Void = { _, _ in }
    var onMarkViewed: (Story) -> Void = { _ in }
    /// Provider for the public-stories stream. Called when the user opts
    /// in to "see public stories" from the caught-up overlay. Returning
    /// an empty array dismisses the viewer (no public content yet).
    var publicStoriesProvider: () -> [Story] = { [] }

    init(
        stories: [Story],
        startIndex: Int = 0,
        publicStoriesProvider: @escaping () -> [Story] = { [] }
    ) {
        _stories = State(initialValue: stories)
        _index = State(initialValue: max(0, min(startIndex, stories.count - 1)))
        self.publicStoriesProvider = publicStoriesProvider
    }

    private let storyDuration: Double = 5.0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            content
            progressBar
                .padding(.top, 40)
                .padding(.horizontal, 12)
            closeButton
                .padding(.top, 40)
                .padding(.trailing, 12)
            replyAndReactBar

            // v4.3 Item 13 — Discover transition overlay when user is caught up.
            // Honors v4.3 §11 Discover Engine surface audit (`storiesPublicOptIn`).
            if v43ShowingCaughtUpOverlay {
                Color.black.opacity(0.92).ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("you're caught up")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text("see public stories from your gym?")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                    HStack(spacing: 12) {
                        Button("see public stories") {
                            // Audit hook — engine is allowed to feed here per design §11.
                            try? DiscoverEngineSurfaceAudit.allow(surface: .storiesPublicOptIn)
                            // Swap the viewer's stream to the public set.
                            // Empty array means there's no public content
                            // available locally yet — fall back to dismiss.
                            let publicSet = publicStoriesProvider()
                            if publicSet.isEmpty {
                                dismiss()
                            } else {
                                stories = publicSet
                                index = 0
                                elapsed = 0
                                v43ShowingCaughtUpOverlay = false
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                        .foregroundStyle(.white)

                        Button("done") { dismiss() }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .zIndex(80)
            }
        }
        .gesture(advanceGesture)
        .onAppear { onMarkViewed(stories[index]) }
        .task(id: index) {
            // Don't run progress while the caught-up overlay is shown.
            if !v43ShowingCaughtUpOverlay { await runProgress() }
        }
    }

    @State private var v43ShowingCaughtUpOverlay: Bool = false
    @State private var v43DiscoverBackfillShown: Bool = false

    @ViewBuilder
    private var content: some View {
        let story = stories[index]
        VStack {
            Spacer()
            switch story.kind {
            case .text:
                Text(story.textBody ?? "")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding()
            case .photo, .video, .workoutShare:
                if let urlString = story.mediaURL, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        (phase.image ?? Image(systemName: "photo"))
                            .resizable().scaledToFit()
                    }
                    .padding()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 80))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            Spacer()
        }
    }

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(stories.indices, id: \.self) { i in
                progressSegment(for: i)
            }
        }
    }

    @ViewBuilder
    private func progressSegment(for i: Int) -> some View {
        GeometryReader { geo in
            let progressWidth = segmentWidth(for: i, total: geo.size.width)
            Capsule().fill(.white.opacity(0.20))
                .overlay(alignment: .leading) {
                    Capsule().fill(.white).frame(width: progressWidth)
                }
        }
        .frame(height: 2)
    }

    private func segmentWidth(for i: Int, total: CGFloat) -> CGFloat {
        if i < index { return total }
        if i == index { return total * CGFloat(elapsed / storyDuration) }
        return 0
    }

    private var closeButton: some View {
        HStack(spacing: 8) {
            Spacer()
            // v4.3 phase 3B — report a story. Hidden when viewing own story.
            if let currentUserId = currentUserIdForReport,
               stories[index].authorId != currentUserId {
                Menu {
                    Button(role: .destructive) {
                        v43ShowReportSheet = true
                    } label: {
                        Label("report", systemImage: "flag")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(Circle().fill(.black.opacity(0.4)))
                }
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Circle().fill(.black.opacity(0.4)))
            }
        }
        .sheet(isPresented: $v43ShowReportSheet) {
            if let currentUserId = currentUserIdForReport {
                ReportSheetView(
                    reporterId: currentUserId,
                    targetKind: .story,
                    targetId: stories[index].id,
                    targetTitle: "story by @\(stories[index].authorId.uuidString.prefix(6))"
                )
            }
        }
    }

    @State private var v43ShowReportSheet: Bool = false
    /// Caller passes their own UUID so we can both gate the report
    /// menu and pass the reporterId down. Nil hides the report option.
    var currentUserIdForReport: UUID? = nil

    private var replyAndReactBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 8) {
                Button {
                    onReply(stories[index], "wsg")
                } label: {
                    Text("reply")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(Capsule().fill(.white.opacity(0.20)))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                ForEach([LiftReaction.fire, .goat, .monke], id: \.self) { r in
                    Button {
                        onReact(stories[index], r)
                    } label: {
                        Text(r.rawValue).font(.system(size: 22))
                            .padding(8)
                            .background(Circle().fill(.white.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 30)
        }
    }

    private var advanceGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onEnded { value in
                if value.translation.height < -50 {
                    onReply(stories[index], "")
                    return
                }
                if value.translation.width < -40 {
                    next()
                } else if value.translation.width > 40 {
                    previous()
                }
            }
    }

    private func next() {
        if index < stories.count - 1 {
            index += 1
            elapsed = 0
            onMarkViewed(stories[index])
        } else if !v43DiscoverBackfillShown {
            // v4.3 Item 13 — caught-up Discover transition.
            // When user has watched all friend stories, surface a labeled
            // "from your gym" / "trending stories" overlay before dismissing.
            // Skippable. Single highest-engagement turn-of-dead-end.
            v43DiscoverBackfillShown = true
            v43ShowingCaughtUpOverlay = true
        } else {
            dismiss()
        }
    }

    private func previous() {
        if index > 0 {
            index -= 1
            elapsed = 0
            onMarkViewed(stories[index])
        }
    }

    @MainActor
    private func runProgress() async {
        elapsed = 0
        while elapsed < storyDuration {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if !paused { elapsed += 0.05 }
        }
        next()
    }
}
