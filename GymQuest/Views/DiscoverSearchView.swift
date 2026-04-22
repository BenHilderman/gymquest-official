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
    /// Optional workout-type narrowing applied on top of the search
    /// query — "push" / "pull" / "legs" / "cardio" / "yoga" / "hiit".
    /// Set via the browse chips on the idle state or the pill below
    /// the search bar. Nil means no type filter.
    @State private var typeFilter: String? = nil

    @FocusState private var focused: Bool

    @State private var tappedPost: Post?
    @State private var tappedProfileId: UUID?
    @State private var tappedExercise: ExerciseMetadata?

    /// Precomputed search indexes. Built once on appear so every keystroke
    /// scans prebuilt lowercase blobs instead of lowercasing/decoding on
    /// each render. The big win is skipping per-keystroke JSON decoding of
    /// sharedWorkoutData to pull a post's title.
    @State private var postIndex: [PostSearchRow] = []
    @State private var profileIndex: [ProfileSearchRow] = []
    @State private var clubIndex: [ClubSearchRow] = []

    private struct PostSearchRow {
        let post: Post
        let title: String
        let subtitle: String
        let blob: String
        let titleLower: String
        let highlightLower: String
        let typeLower: String
        let authorNameLower: String
        let authorUsernameLower: String
        let isRunnable: Bool
    }

    private struct ProfileSearchRow {
        let profile: UserProfile
        let nameLower: String
        let usernameLower: String
    }

    private struct ClubSearchRow {
        let club: Club
        let blob: String
    }

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
                    .padding(.bottom, 10)

                activeFilterPill

                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    recentsBody
                } else {
                    typingBody
                }
            }
            .gqPageBackground()
            .navigationBarHidden(true)
            .onAppear {
                focused = true
                if postIndex.isEmpty { buildIndexes() }
            }
            .onChange(of: allPosts.count) { _, _ in buildIndexes() }
            .onChange(of: allUserProfiles.count) { _, _ in buildIndexes() }
            .onChange(of: clubs.count) { _, _ in buildIndexes() }
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

    /// Idle state — what the user sees before typing. Shows (in order):
    /// recent searches (if any), quick browse-by-category chips,
    /// trending workouts horizontal rail, and a suggested clubs rail.
    /// Gives the user something to explore even when they don't know
    /// what to type.
    private var recentsBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                if !recents.isEmpty {
                    recentsSection
                }

                browseByCategorySection

                if !suggestedClubs.isEmpty {
                    suggestedClubsSection
                }

                if recents.isEmpty {
                    idleHintFooter
                        .padding(.top, 4)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 60)
        }
    }

    @ViewBuilder
    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
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
            .padding(.bottom, 4)

            ForEach(recents) { entry in
                recentRow(entry)
            }
        }
    }

    private let idleBrowseCategories: [(label: String, icon: String, query: String)] = [
        ("Push", "figure.strengthtraining.traditional", "push"),
        ("Pull", "figure.cross.training", "pull"),
        ("Legs", "figure.walk", "legs"),
        ("Cardio", "flame.fill", "cardio"),
        ("Yoga", "figure.mind.and.body", "yoga"),
        ("HIIT", "bolt.heart.fill", "hiit"),
    ]

    @ViewBuilder
    private var browseByCategorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Filter by workout type")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(GQColors.textPrimary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(idleBrowseCategories, id: \.label) { item in
                        let selected = typeFilter == item.query
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                typeFilter = selected ? nil : item.query
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(item.label)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundColor(selected ? .white : GQColors.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(selected
                                    ? AnyShapeStyle(GQGradients.primary)
                                    : AnyShapeStyle(GQColors.adaptiveOverlay(0.06)))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    /// Pill shown below the search bar when a type filter is active —
    /// gives the user a clear "Filter: Pull ×" affordance to clear it.
    @ViewBuilder
    private var activeFilterPill: some View {
        if let filter = typeFilter {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { typeFilter = nil }
                } label: {
                    HStack(spacing: 4) {
                        Text("Filter:")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.85))
                        Text(filter.capitalized)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(GQGradients.primary))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    /// Top 5 public clubs the user has not joined, ranked by member
    /// count — a quick "join one of these" surface in the idle state.
    private var suggestedClubs: [Club] {
        let followedIds = Set(profile.id == profile.id ? [] as [UUID] : [])
        _ = followedIds
        let myClubIds = Set(clubs.filter { $0.memberIds.contains(profile.id) }.map(\.id))
        return clubs
            .filter { $0.parentClubId == nil && !myClubIds.contains($0.id) && $0.isOpen }
            .sorted { $0.memberCount > $1.memberCount }
            .prefix(5)
            .map { $0 }
    }

    @ViewBuilder
    private var suggestedClubsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
                Text("Clubs you might like")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
            }
            .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(Array(suggestedClubs.enumerated()), id: \.element.id) { idx, club in
                    Button {
                        appState.selectedTab = .clubs
                        dismiss()
                    } label: {
                        suggestedClubRow(club)
                    }
                    .buttonStyle(.plain)
                    if idx < suggestedClubs.count - 1 {
                        Divider()
                            .overlay(GQColors.adaptiveOverlay(0.08))
                            .padding(.leading, 68)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func suggestedClubRow(_ club: Club) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(GQGradients.primary)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(club.name.prefix(1)).uppercased())
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(club.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                Text(clubSubtitle(club))
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(GQColors.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var idleHintFooter: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 22))
                .foregroundColor(GQColors.textTertiary)
            Text("Search workouts, exercises, people, clubs")
                .font(.system(size: 12))
                .foregroundColor(GQColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
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
        // Prefer opening a real post featuring this exercise — same
        // format the user sees elsewhere in the app. Fall back to the
        // metadata sheet only when no post highlights this exercise.
        if let post = featuredPost(for: meta) {
            tappedPost = post
        } else {
            tappedExercise = meta
        }
    }

    /// Pick the best post that features a given exercise. Prefers
    /// runnable shared workouts where the exercise appears in the
    /// title or exercise list, falls back to posts whose exercise
    /// highlight matches the name.
    private func featuredPost(for meta: ExerciseMetadata) -> Post? {
        let name = meta.name.lowercased()
        // First pass: shared-workout posts whose exercise list contains this name.
        let shared = allPosts.first { post in
            guard let data = post.sharedWorkoutData,
                  let decoded = try? JSONDecoder().decode(SharedWorkoutData.self, from: data) else { return false }
            return decoded.title.lowercased().contains(name)
                || decoded.exercises.contains { $0.name.lowercased().contains(name) }
        }
        if let shared { return shared }
        // Second pass: any post whose exerciseHighlight matches.
        return allPosts.first {
            ($0.exerciseHighlight?.lowercased().contains(name) ?? false)
            && ($0.photoData != nil || $0.videoData != nil || !$0.mediaItems.isEmpty)
        }
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
        var results: [(Post, Int)] = []
        results.reserveCapacity(perTabCap * 2)
        for row in postIndex {
            // Type filter narrows the pool first — "pull" means only
            // pull-tagged posts survive, regardless of text score.
            if let filter = typeFilter, !row.typeLower.contains(filter) { continue }
            guard row.blob.contains(q) else { continue }  // fast prefilter
            var score = 0
            if row.titleLower.contains(q) { score += 4 }
            if row.highlightLower.contains(q) { score += 3 }
            if row.typeLower.contains(q) { score += 2 }
            if row.authorNameLower.contains(q) { score += 2 }
            if row.authorUsernameLower.contains(q) { score += 2 }
            if row.isRunnable { score += 1 }
            if score > 0 { results.append((row.post, score)) }
        }
        return results.sorted { $0.1 > $1.1 }.prefix(perTabCap).map { $0.0 }
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
        var matches: [UserProfile] = []
        matches.reserveCapacity(perTabCap)
        for row in profileIndex {
            if row.nameLower.contains(q) || row.usernameLower.contains(q) {
                matches.append(row.profile)
                if matches.count >= perTabCap { break }
            }
        }
        return matches
    }

    private var matchedClubs: [Club] {
        guard !q.isEmpty else { return [] }
        var matches: [Club] = []
        matches.reserveCapacity(perTabCap)
        for row in clubIndex {
            if row.blob.contains(q) {
                matches.append(row.club)
                if matches.count >= perTabCap { break }
            }
        }
        return matches
    }

    // MARK: - Index build

    /// Build lowercased search indexes once so every keystroke reuses
    /// precomputed blobs instead of lowercasing + JSON-decoding on each
    /// render. Capped to the most recent 300 posts — search UX doesn't
    /// need to scan the entire corpus.
    private func buildIndexes() {
        let postCap = 300
        let recentPosts = Array(allPosts.prefix(postCap))

        postIndex = recentPosts.map { post in
            let title = postTitle(post)
            let subtitle = workoutSubtitle(post)
            let titleLower = title.lowercased()
            let highlightLower = (post.exerciseHighlight ?? "").lowercased()
            let typeLower = (post.workoutType ?? "").lowercased()
            let authorNameLower = post.authorName.lowercased()
            let authorUsernameLower = post.authorUsername.lowercased()
            let blob = [titleLower, highlightLower, typeLower, authorNameLower, authorUsernameLower].joined(separator: " ")
            return PostSearchRow(
                post: post,
                title: title,
                subtitle: subtitle,
                blob: blob,
                titleLower: titleLower,
                highlightLower: highlightLower,
                typeLower: typeLower,
                authorNameLower: authorNameLower,
                authorUsernameLower: authorUsernameLower,
                isRunnable: post.sharedWorkoutData != nil
            )
        }

        profileIndex = allUserProfiles
            .filter { $0.id != profile.id }
            .map {
                ProfileSearchRow(
                    profile: $0,
                    nameLower: $0.name.lowercased(),
                    usernameLower: $0.username.lowercased()
                )
            }

        clubIndex = clubs.map { club in
            let blob = [
                club.name.lowercased(),
                club.location?.lowercased() ?? "",
                club.resolvedCategory.rawValue.lowercased()
            ].joined(separator: " ")
            return ClubSearchRow(club: club, blob: blob)
        }
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
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(GQColors.textTertiary)
            Text("No results for “\(query)”")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(GQColors.textPrimary)
            Text("Try a different word or browse by category.")
                .font(.system(size: 12))
                .foregroundColor(GQColors.textTertiary)
                .multilineTextAlignment(.center)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(idleBrowseCategories, id: \.label) { item in
                        Button {
                            rawQuery = item.query
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(item.label)
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(GQColors.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(GQColors.adaptiveOverlay(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 6)
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
