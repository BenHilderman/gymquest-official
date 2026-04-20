import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

/// Instagram-style search: recent ring when idle, segmented tabs when
/// typing, rich media thumbnails on every row. Four real content surfaces
/// are searched — Workouts, Exercises, People, Clubs — with a Top tab
/// that blends best matches across all.
struct DiscoverSearchView: View {
    let profile: UserProfile

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var appState: AppState

    @Query(sort: \Post.timestamp, order: .reverse) private var allPosts: [Post]
    @Query private var allUserProfiles: [UserProfile]
    @Query private var clubs: [Club]

    @State private var rawQuery: String = ""
    @State private var query: String = ""
    @State private var selectedTab: SearchTab = .top
    @State private var recents: [RecentSearchEntry] = RecentSearchStore.load()

    @FocusState private var focused: Bool

    @State private var tappedPost: Post?
    @State private var tappedProfileId: UUID?
    @State private var tappedExercise: ExerciseMetadata?

    private let perTabCap = 12
    private let topPerSection = 3

    enum SearchTab: String, CaseIterable, Identifiable {
        case top, workouts, exercises, people, clubs
        var id: String { rawValue }
        var label: String {
            switch self {
            case .top: return "Top"
            case .workouts: return "Workouts"
            case .exercises: return "Exercises"
            case .people: return "People"
            case .clubs: return "Clubs"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    recentsBody
                } else {
                    typingBody
                }
            }
            .gqPageBackground()
            .navigationBarHidden(true)
            .onAppear { focused = true }
            .task(id: rawQuery) {
                try? await Task.sleep(nanoseconds: 220_000_000)
                query = rawQuery
            }
            .fullScreenCover(item: $tappedPost) { post in
                PostDetailView(post: post, profile: profile)
            }
            .sheet(item: Binding(
                get: { tappedProfileId.map { IdentifiableUUID(id: $0) } },
                set: { tappedProfileId = $0?.id }
            )) { wrapped in
                UserProfileSheet(userId: wrapped.id, currentProfile: profile)
            }
            .sheet(item: $tappedExercise) { meta in
                NavigationStack { ExerciseDetailSheet(metadata: meta) }
            }
        }
        .tint(GQColors.textPrimary)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(GQColors.textTertiary)
                TextField("Workouts, exercises, people, clubs", text: $rawQuery)
                    .font(.system(size: 15))
                    .foregroundColor(GQColors.textPrimary)
                    .submitLabel(.search)
                    .focused($focused)
                    .autocorrectionDisabled()
                if !rawQuery.isEmpty {
                    Button {
                        rawQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(GQColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(GQColors.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(GQColors.borderDefault, lineWidth: 1))

            Button("Cancel") { dismiss() }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(GQColors.textSecondary)
                .buttonStyle(.plain)
        }
    }

    // MARK: - Recents (idle state)

    private var recentsBody: some View {
        ScrollView {
            if recents.isEmpty {
                emptyState
                    .padding(.top, 60)
            } else {
                LazyVStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Recent")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(GQColors.textPrimary)
                        Spacer()
                        Button("Clear all") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                RecentSearchStore.clearAll()
                                recents = []
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundColor(GQColors.textSecondary)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)

                    ForEach(recents) { entry in
                        recentRow(entry)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }

    private func recentRow(_ entry: RecentSearchEntry) -> some View {
        HStack(spacing: 12) {
            recentThumbnail(entry)
                .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                if let sub = entry.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundColor(GQColors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    RecentSearchStore.remove(id: entry.id)
                    recents = RecentSearchStore.load()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(GQColors.textTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            handleRecentTap(entry)
        }
    }

    @ViewBuilder
    private func recentThumbnail(_ entry: RecentSearchEntry) -> some View {
        #if canImport(UIKit)
        if let data = entry.thumbnailData, let img = UIImage(data: data) {
            switch entry.kind {
            case .person:
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fill).clipShape(Circle())
            default:
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fill).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        } else {
            placeholderThumbnail(for: entry.kind)
        }
        #else
        placeholderThumbnail(for: entry.kind)
        #endif
    }

    @ViewBuilder
    private func placeholderThumbnail(for kind: RecentSearchEntry.Kind) -> some View {
        let icon: String = {
            switch kind {
            case .workout: return "figure.strengthtraining.traditional"
            case .exercise: return "figure.core.training"
            case .person: return "person.fill"
            case .club: return "person.3.fill"
            case .query: return "magnifyingglass"
            }
        }()
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(GQGradients.primary.opacity(0.12))
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(GQGradients.primary)
        }
        .clipShape(kind == .person ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10)))
    }

    private func handleRecentTap(_ entry: RecentSearchEntry) {
        RecentSearchStore.add(entry)   // promote to top
        recents = RecentSearchStore.load()
        switch entry.kind {
        case .workout:
            if let id = entry.subjectId, let post = allPosts.first(where: { $0.id == id }) {
                tappedPost = post
            }
        case .person:
            if let id = entry.subjectId { tappedProfileId = id }
        case .exercise:
            if let meta = ExtendedExerciseDatabase.exercises.first(where: { $0.name.lowercased() == entry.label.lowercased() }) {
                tappedExercise = meta
            }
        case .club:
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                appState.selectedTab = .clubs
            }
        case .query:
            rawQuery = entry.label
        }
    }

    // MARK: - Typing state (tabs + results)

    private var typingBody: some View {
        VStack(spacing: 0) {
            tabBar

            if noResults {
                noResultsState.padding(.top, 60)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        switch selectedTab {
                        case .top: topResults
                        case .workouts: listResults(matchedWorkouts.map(workoutEntry))
                        case .exercises: listResults(matchedExercises.map(exerciseEntry))
                        case .people: listResults(matchedPeople.map(personEntry))
                        case .clubs: listResults(matchedClubs.map(clubEntry))
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SearchTab.allCases) { tab in
                    let selected = tab == selectedTab
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { selectedTab = tab }
                    } label: {
                        Text(tab.label)
                            .font(.system(size: 13, weight: selected ? .semibold : .medium))
                            .foregroundColor(selected ? .white : GQColors.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                selected
                                    ? AnyShapeStyle(GQGradients.primary)
                                    : AnyShapeStyle(GQColors.adaptiveOverlay(0.05))
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var topResults: some View {
        // Top = top N of each category, in priority order. Section headers
        // group them so users can still scan by type inside the blended tab.
        if !matchedWorkouts.isEmpty {
            sectionHeader("WORKOUTS").padding(.horizontal, 16)
            listResults(matchedWorkouts.prefix(topPerSection).map(workoutEntry))
        }
        if !matchedPeople.isEmpty {
            sectionHeader("PEOPLE").padding(.horizontal, 16).padding(.top, 8)
            listResults(matchedPeople.prefix(topPerSection).map(personEntry))
        }
        if !matchedClubs.isEmpty {
            sectionHeader("CLUBS").padding(.horizontal, 16).padding(.top, 8)
            listResults(matchedClubs.prefix(topPerSection).map(clubEntry))
        }
        if !matchedExercises.isEmpty {
            sectionHeader("EXERCISES").padding(.horizontal, 16).padding(.top, 8)
            listResults(matchedExercises.prefix(topPerSection).map(exerciseEntry))
        }
    }

    // MARK: - Result row (unified)

    /// One result payload the unified row renders. Each matcher converts
    /// its domain object into this struct so the row code stays simple.
    private struct RowEntry: Identifiable {
        let id: String
        let thumbnail: ThumbnailKind
        let title: String
        let subtitle: String
        let trailing: String?
        let onTap: () -> Void

        enum ThumbnailKind {
            case post(Post)
            case profile(UserProfile)
            case exerciseIcon
            case clubIcon
        }
    }

    private func listResults<S: Sequence>(_ entries: S) -> some View where S.Element == RowEntry {
        VStack(spacing: 4) {
            ForEach(Array(entries)) { entry in
                Button { entry.onTap() } label: {
                    resultRow(entry)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func resultRow(_ entry: RowEntry) -> some View {
        HStack(spacing: 12) {
            thumbnailView(entry.thumbnail)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                Text(entry.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            if let trailing = entry.trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(GQGradients.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func thumbnailView(_ kind: RowEntry.ThumbnailKind) -> some View {
        switch kind {
        case .post(let post):
            postThumbnail(post)
        case .profile(let profile):
            profileThumbnail(profile)
        case .exerciseIcon:
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(GQColors.surfaceBase)
                Image(systemName: "figure.core.training")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(GQColors.textSecondary)
            }
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(GQColors.borderDefault, lineWidth: 1))
        case .clubIcon:
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(GQGradients.primary.opacity(0.12))
                Image(systemName: "person.3.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
            }
        }
    }

    @ViewBuilder
    private func postThumbnail(_ post: Post) -> some View {
        #if canImport(UIKit)
        if let data = primaryPostThumbData(post), let img = UIImage(data: data) {
            ZStack(alignment: .bottomTrailing) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if isVideoPost(post) {
                    // Play badge — mirrors Instagram's reel indicator so
                    // you instantly see it's video without playing it.
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .padding(4)
                }
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(GQGradients.primary.opacity(0.12))
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
            }
        }
        #else
        RoundedRectangle(cornerRadius: 10).fill(GQColors.surfaceSecondary)
        #endif
    }

    @ViewBuilder
    private func profileThumbnail(_ profile: UserProfile) -> some View {
        #if canImport(UIKit)
        if let data = profile.profilePhotoData, let img = UIImage(data: data) {
            Image(uiImage: img).resizable().aspectRatio(contentMode: .fill).clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(GQGradients.primary)
                Text(String(profile.name.prefix(1)).uppercased())
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        #else
        Circle().fill(GQColors.surfaceSecondary)
        #endif
    }

    // MARK: - Entry builders

    private func workoutEntry(_ post: Post) -> RowEntry {
        RowEntry(
            id: "w-\(post.id.uuidString)",
            thumbnail: .post(post),
            title: postTitle(post),
            subtitle: workoutSubtitle(post),
            trailing: post.sharedWorkoutData != nil ? "Try →" : nil,
            onTap: { openWorkout(post) }
        )
    }

    private func exerciseEntry(_ meta: ExerciseMetadata) -> RowEntry {
        RowEntry(
            id: "e-\(meta.id.uuidString)",
            thumbnail: .exerciseIcon,
            title: meta.name,
            subtitle: "\(meta.muscleGroup.rawValue.capitalized) · \(meta.equipment.rawValue.capitalized)",
            trailing: nil,
            onTap: { openExercise(meta) }
        )
    }

    private func personEntry(_ person: UserProfile) -> RowEntry {
        RowEntry(
            id: "p-\(person.id.uuidString)",
            thumbnail: .profile(person),
            title: person.name,
            subtitle: person.username.isEmpty ? "" : "@\(person.username)",
            trailing: nil,
            onTap: { openPerson(person) }
        )
    }

    private func clubEntry(_ club: Club) -> RowEntry {
        RowEntry(
            id: "c-\(club.id.uuidString)",
            thumbnail: .clubIcon,
            title: club.name,
            subtitle: clubSubtitle(club),
            trailing: nil,
            onTap: { openClub(club) }
        )
    }

    // MARK: - Tap handlers (record + navigate)

    private func openWorkout(_ post: Post) {
        RecentSearchStore.add(RecentSearchEntry(
            kind: .workout,
            subjectId: post.id,
            label: postTitle(post),
            subtitle: workoutSubtitle(post),
            thumbnailData: primaryPostThumbData(post)
        ))
        recents = RecentSearchStore.load()
        tappedPost = post
    }

    private func openExercise(_ meta: ExerciseMetadata) {
        RecentSearchStore.add(RecentSearchEntry(
            kind: .exercise,
            label: meta.name,
            subtitle: "\(meta.muscleGroup.rawValue.capitalized) · \(meta.equipment.rawValue.capitalized)"
        ))
        recents = RecentSearchStore.load()
        tappedExercise = meta
    }

    private func openPerson(_ person: UserProfile) {
        RecentSearchStore.add(RecentSearchEntry(
            kind: .person,
            subjectId: person.id,
            label: person.name,
            subtitle: person.username.isEmpty ? nil : "@\(person.username)",
            thumbnailData: person.profilePhotoData
        ))
        recents = RecentSearchStore.load()
        tappedProfileId = person.id
    }

    private func openClub(_ club: Club) {
        RecentSearchStore.add(RecentSearchEntry(
            kind: .club,
            subjectId: club.id,
            label: club.name,
            subtitle: clubSubtitle(club)
        ))
        recents = RecentSearchStore.load()
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            appState.selectedTab = .clubs
        }
    }

    // MARK: - Matching

    private var q: String { query.lowercased().trimmingCharacters(in: .whitespaces) }

    private var noResults: Bool {
        matchedWorkouts.isEmpty && matchedExercises.isEmpty && matchedPeople.isEmpty && matchedClubs.isEmpty
    }

    private var matchedWorkouts: [Post] {
        guard !q.isEmpty else { return [] }
        let scored = allPosts.compactMap { post -> (Post, Int)? in
            var score = 0
            if postTitle(post).lowercased().contains(q) { score += 4 }
            if (post.exerciseHighlight ?? "").lowercased().contains(q) { score += 3 }
            if (post.workoutType ?? "").lowercased().contains(q) { score += 2 }
            if post.authorName.lowercased().contains(q) { score += 2 }
            if post.authorUsername.lowercased().contains(q) { score += 2 }
            if post.sharedWorkoutData != nil { score += 1 }
            return score > 0 ? (post, score) : nil
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(perTabCap).map { $0.0 }
    }

    private var matchedExercises: [ExerciseMetadata] {
        guard !q.isEmpty else { return [] }
        return ExtendedExerciseDatabase.exercises
            .filter { meta in
                meta.name.lowercased().contains(q) ||
                meta.aliases.contains(where: { $0.lowercased().contains(q) }) ||
                meta.primaryMuscles.contains(where: { $0.lowercased().contains(q) })
            }
            .prefix(perTabCap)
            .map { $0 }
    }

    private var matchedPeople: [UserProfile] {
        guard !q.isEmpty else { return [] }
        return allUserProfiles
            .filter { $0.id != profile.id }
            .filter { $0.name.lowercased().contains(q) || $0.username.lowercased().contains(q) }
            .prefix(perTabCap)
            .map { $0 }
    }

    private var matchedClubs: [Club] {
        guard !q.isEmpty else { return [] }
        return clubs
            .filter { club in
                club.name.lowercased().contains(q) ||
                (club.location?.lowercased().contains(q) ?? false) ||
                club.resolvedCategory.rawValue.lowercased().contains(q)
            }
            .prefix(perTabCap)
            .map { $0 }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(GQColors.textTertiary)
            Text("Find workouts, exercises, people, and clubs")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(GQColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(GQColors.textTertiary)
            Text("No results for “\(query)”")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(GQColors.textSecondary)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(GQColors.textTertiary)
    }

    private func postTitle(_ post: Post) -> String {
        if let data = post.sharedWorkoutData,
           let shared = try? JSONDecoder().decode(SharedWorkoutData.self, from: data),
           !shared.title.isEmpty { return shared.title }
        return post.exerciseHighlight ?? post.workoutType?.capitalized ?? "Workout"
    }

    private func workoutSubtitle(_ post: Post) -> String {
        var parts: [String] = []
        if let dur = post.duration, dur > 0 { parts.append("\(dur) min") }
        if let type = post.workoutType { parts.append(type.capitalized) }
        parts.append("@\(post.authorUsername)")
        return parts.joined(separator: " · ")
    }

    private func clubSubtitle(_ club: Club) -> String {
        var parts: [String] = [club.resolvedCategory.rawValue.capitalized]
        if let loc = club.location, !loc.isEmpty { parts.append(loc) }
        parts.append("\(club.memberIds.count) members")
        return parts.joined(separator: " · ")
    }

    private func primaryPostThumbData(_ post: Post) -> Data? {
        if let first = post.mediaItems.first { return first.thumbnailData ?? first.data }
        return post.photoData
    }

    private func isVideoPost(_ post: Post) -> Bool {
        if let v = post.videoData, v.count >= 1024 { return true }
        return post.mediaItems.contains(where: { ($0.data?.count ?? 0) >= 1024 && $0.mediaType == .video })
    }
}

/// Simple AnyShape eraser — needed because clipShape doesn't accept a
/// conditional AnyView / Shape choice inline.
private struct AnyShape: Shape {
    private let path: (CGRect) -> Path
    init<S: Shape>(_ wrapped: S) { path = { rect in wrapped.path(in: rect) } }
    func path(in rect: CGRect) -> Path { path(rect) }
}

/// Minimal sheet for exercise details — reuses metadata cues/mistakes/
/// variations already in ExtendedExerciseDatabase.
private struct ExerciseDetailSheet: View {
    let metadata: ExerciseMetadata
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(metadata.name)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(GQColors.textPrimary)
                    Text("\(metadata.muscleGroup.rawValue.capitalized) · \(metadata.equipment.rawValue.capitalized) · \(metadata.difficulty.rawValue.capitalized)")
                        .font(.system(size: 13))
                        .foregroundColor(GQColors.textTertiary)
                }

                if !metadata.cues.isEmpty {
                    infoBlock(title: "FORM CUES", items: metadata.cues, icon: "checkmark.circle.fill", tint: GQColors.success)
                }
                if !metadata.commonMistakes.isEmpty {
                    infoBlock(title: "COMMON MISTAKES", items: metadata.commonMistakes, icon: "exclamationmark.triangle.fill", tint: .orange)
                }
                if !metadata.variations.isEmpty {
                    infoBlock(title: "VARIATIONS", items: metadata.variations, icon: "arrow.triangle.branch", tint: GQColors.deepBlue)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .gqPageBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundColor(GQColors.textPrimary)
            }
        }
    }

    private func infoBlock(title: String, items: [String], icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(GQColors.textTertiary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(tint)
                            .padding(.top, 2)
                        Text(item)
                            .font(.system(size: 13))
                            .foregroundColor(GQColors.textPrimary)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(12)
            .homeSocialCard(cornerRadius: 12)
        }
    }
}
