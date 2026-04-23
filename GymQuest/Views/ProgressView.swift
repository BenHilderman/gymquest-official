//
//  ProgressView.swift
//  GymQuest
//
//  Visual analytics — rings, charts, and trends.
//

import SwiftUI
import SwiftData
import Charts

struct ProgressAnalyticsView: View {
    @Query(sort: \PREvent.date, order: .reverse) private var prEvents: [PREvent]
    @Query(sort: \Workout.date, order: .reverse) private var workouts: [Workout]
    @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
    @Query(sort: \UserGoal.createdAt, order: .reverse) private var allGoals: [UserGoal]

    @Environment(\.modelContext) private var modelContext

    let profile: UserProfile
    var inline: Bool = false
    /// Optional anchor — when set (e.g. "nutrition" or "weight") the
    /// page scrolls to that section on appear. Used by the log sheets'
    /// "Progress" toolbar button to deep-link to the relevant chart.
    var scrollTarget: String? = nil

    @State private var selectedExerciseName: String = ""
    @State private var showingExerciseTrend = false
    @State private var animateRings: CGFloat = 0
    @State private var showingAddGoal = false

    private var activeGoals: [UserGoal] {
        allGoals.filter { $0.userId == profile.id && $0.achievedAt == nil }
    }

    private var achievedGoals: [UserGoal] {
        allGoals.filter { $0.userId == profile.id && $0.achievedAt != nil }
    }

    private var validWorkouts: [Workout] {
        workouts.filter { $0.type != .rest }
    }

    private var recentPRs: [PREvent] { Array(prEvents.prefix(5)) }

    private var weeklyVolumes: [(weekLabel: String, volume: Double)] {
        let calendar = Calendar.current
        let now = Date()
        var result: [(String, Double)] = []
        for weeksAgo in (0..<6).reversed() {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: now) else { continue }
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? now
            let weekWorkouts = validWorkouts.filter { $0.date >= weekStart && $0.date < weekEnd }
            var vol: Double = 0
            for w in weekWorkouts { for ex in w.exercises { for s in ex.sets { vol += Double(s.weight) * Double(s.reps) } } }
            result.append((weekStart.formatted(.dateTime.month(.abbreviated).day()), vol))
        }
        return result
    }

    private var workoutSplit: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for w in Array(validWorkouts.prefix(30)) { counts[w.type.rawValue, default: 0] += 1 }
        return counts.map { (name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }

    private var allExerciseNames: [String] {
        var names = Set<String>()
        for w in workouts { for ex in w.exercises { names.insert(ex.name) } }
        return names.sorted()
    }

    private var totalWorkouts: Int { validWorkouts.count }
    private var totalPRs: Int { prEvents.count }

    private var thisWeekWorkouts: Int {
        let calendar = Calendar.current
        guard let start = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        return validWorkouts.filter { $0.date >= start }.count
    }

    /// Week-over-week volume trend. Forgiving rules so a partial week
    /// doesn't read as "Down 100%":
    /// - If either week has 0 volume → return 0 (rendered as neutral).
    /// - If the current week is less than ~40% complete → return 0;
    ///   comparing a Tuesday against a full prior week is unfair.
    /// - Clamp the result to ±150% so a blowup (10×) doesn't dominate
    ///   the ring.
    private var volumeTrend: Double {
        guard weeklyVolumes.count >= 2 else { return 0 }
        let last = weeklyVolumes.last?.volume ?? 0
        let prev = weeklyVolumes[weeklyVolumes.count - 2].volume
        guard prev > 0, last > 0 else { return 0 }

        // Partial-week fairness: only compare after ~3 days elapsed.
        let weekday = Calendar.current.component(.weekday, from: Date())
        // weekday is 1..7 (Sun..Sat); convert to 0..6 days-into-week
        // with Monday-start to keep parity with the weeklyVolumes grouping.
        let daysIntoWeek = max(0, weekday - 2)
        if daysIntoWeek < 3 { return 0 }

        let raw = ((last - prev) / prev) * 100
        return max(-150, min(150, raw))
    }

    private var weightMeasurements: [BodyMeasurement] {
        measurements.filter { $0.type == .weight }.sorted { $0.date < $1.date }
    }

    private var latestWeight: Double? { weightMeasurements.last?.value }

    private var weightChange: Double? {
        guard weightMeasurements.count >= 2 else { return nil }
        return weightMeasurements.last!.value - weightMeasurements[weightMeasurements.count - 2].value
    }

    var body: some View {
        if inline {
            analyticsContent
        } else {
            ScrollViewReader { proxy in
                ScrollView { analyticsContent }
                    .gqPageBackground()
                    .navigationTitle("Progress")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarBackground(GQColors.background, for: .navigationBar)
                    .instagramBack()
                    .onAppear {
                        guard let target = scrollTarget else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                proxy.scrollTo(target, anchor: .top)
                            }
                        }
                    }
            }
        }
    }

    // MARK: - Content

    private var analyticsContent: some View {
        VStack(spacing: 20) {
            heroSummary
            goalsSection
            ringStatsRow
            volumeCard
            splitAndBodyRow
                .id("weight")
            nutritionCard
                .id("nutrition")
            if !recentPRs.isEmpty { prsCard }
            exerciseTrendCard
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 100)
        .sheet(isPresented: $showingAddGoal) {
            AddGoalSheet(profile: profile)
        }
        .onAppear {
            animateRings = 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 1.4)) {
                    animateRings = 1
                }
            }
        }
        .animation(.easeInOut(duration: 1.4), value: animateRings)
    }

    // MARK: - Hero Summary

    private var heroSummary: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(totalWorkouts)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(GQGradients.primary)
                Text("total workouts")
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: abs(volumeTrend) < 1 ? "minus" : (volumeTrend > 0 ? "arrow.up.right" : "arrow.down.right"))
                        .font(.system(size: 11, weight: .bold))
                    Text(String(format: "%.0f%%", abs(volumeTrend)))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundColor(abs(volumeTrend) < 1 ? GQColors.textSecondary : (volumeTrend > 0 ? GQColors.success : GQColors.textSecondary))
                Text("volume trend")
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Ring Stats

    @ViewBuilder
    private var ringStatsRow: some View {
        HStack(spacing: 0) {
            ringColumn(
                value: thisWeekWorkouts,
                target: profile.daysPerWeek,
                centerText: "\(thisWeekWorkouts)/\(profile.daysPerWeek)",
                label: "This Week",
                gradient: GQGradients.primary
            )

            thinDivider

            ringColumn(
                value: min(totalPRs, 10),
                target: 10,
                centerText: "\(totalPRs)",
                label: "PRs",
                gradient: LinearGradient(colors: [GQColors.cyanSpark, GQColors.deepBlue], startPoint: .topLeading, endPoint: .bottomTrailing)
            )

            thinDivider

            volumeRingColumn
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .homeSocialCard(cornerRadius: 14)
    }

    private func ringColumn(value: Int, target: Int, centerText: String, label: String, gradient: LinearGradient) -> some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(GQColors.adaptiveOverlay(0.04), lineWidth: 5)
                    .frame(width: 48, height: 48)
                Circle()
                    .trim(from: 0, to: (target > 0 ? min(CGFloat(value) / CGFloat(target), 1.0) : 0) * animateRings)
                    .stroke(gradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 48, height: 48)

                Text(centerText)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(GQColors.textPrimary)
            }

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(GQColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var volumeRingColumn: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(GQColors.adaptiveOverlay(0.04), lineWidth: 5)
                    .frame(width: 48, height: 48)
                Circle()
                    .trim(from: 0, to: min(abs(volumeTrend) / 100, 1.0) * animateRings)
                    .stroke(
                        abs(volumeTrend) < 1
                            ? LinearGradient(colors: [GQColors.textSecondary, GQColors.textTertiary], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : (volumeTrend > 0 ? GQGradients.primary : LinearGradient(colors: [GQColors.textSecondary, GQColors.textTertiary], startPoint: .topLeading, endPoint: .bottomTrailing)),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 48, height: 48)

                HStack(spacing: 1) {
                    Image(systemName: abs(volumeTrend) < 1 ? "minus" : (volumeTrend > 0 ? "arrow.up" : "arrow.down"))
                        .font(.system(size: 8, weight: .bold))
                    Text(String(format: "%.0f%%", abs(volumeTrend)))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundColor(GQColors.textPrimary)
            }

            Text("Volume")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(GQColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(GQColors.borderSubtle)
            .frame(width: 0.5, height: 50)
    }

    // MARK: - Volume Card

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Weekly Volume")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Spacer()
                if let lastVol = weeklyVolumes.last?.volume, lastVol > 0 {
                    Text(lastVol >= 1000 ? String(format: "%.1fk", lastVol / 1000) : "\(Int(lastVol))")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(GQGradients.primary)
                    + Text(" lbs")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(GQColors.textTertiary)
                }
            }

            if weeklyVolumes.allSatisfy({ $0.volume == 0 }) {
                emptyState(icon: "chart.bar", text: "Log workouts to see volume trends")
            } else {
                volumeChart
            }
        }
        .padding(16)
        .homeSocialCard(cornerRadius: 14)
    }

    @ViewBuilder
    private var volumeChart: some View {
        Chart(weeklyVolumes, id: \.weekLabel) { item in
            BarMark(
                x: .value("Week", item.weekLabel),
                y: .value("Volume", item.volume),
                width: .fixed(20)
            )
            .foregroundStyle(GQGradients.primary)
            .cornerRadius(6)
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v >= 1000 ? "\(Int(v / 1000))k" : "\(Int(v))")
                            .font(.system(size: 10))
                            .foregroundColor(GQColors.textTertiary)
                    }
                }
                AxisGridLine()
                    .foregroundStyle(GQColors.adaptiveOverlay(0.04))
            }
        }
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.system(size: 9))
                            .foregroundColor(GQColors.textTertiary)
                    }
                }
            }
        }
        .frame(height: 150)
    }

    // MARK: - Split & Body Side by Side

    private var splitAndBodyRow: some View {
        HStack(alignment: .top, spacing: 12) {
            splitCard
            bodyProgressCard
        }
    }

    // MARK: - Split Card

    private var splitCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Split")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Spacer()
                Text("Last 30")
                    .font(.system(size: 10))
                    .foregroundColor(GQColors.textTertiary)
            }

            if workoutSplit.isEmpty {
                emptyState(icon: "chart.pie", text: "No data")
            } else {
                splitDonutContent
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .homeSocialCard(cornerRadius: 14)
    }

    @ViewBuilder
    private var splitDonutContent: some View {
        let total = workoutSplit.reduce(0) { $0 + $1.count }

        VStack(spacing: 14) {
            ZStack {
                // Soft glow
                Circle()
                    .fill(GQGradients.primary.opacity(0.06))
                    .frame(width: 95, height: 95)
                    .blur(radius: 10)

                Circle()
                    .stroke(GQColors.adaptiveOverlay(0.03), lineWidth: 11)
                    .frame(width: 84, height: 84)

                ForEach(Array(workoutSplit.enumerated()), id: \.element.name) { index, item in
                    let fraction = total > 0 ? CGFloat(item.count) / CGFloat(total) : 0
                    let startAngle = workoutSplit.prefix(index).reduce(0.0) { acc, s in
                        acc + (total > 0 ? CGFloat(s.count) / CGFloat(total) : 0)
                    }
                    Circle()
                        .trim(from: (startAngle + 0.006) * animateRings, to: (startAngle + fraction - 0.006) * animateRings)
                        .stroke(
                            splitGradient(for: index),
                            style: StrokeStyle(lineWidth: 11, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }

                VStack(spacing: 0) {
                    Text("\(total)")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(GQColors.textPrimary)
                }
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(workoutSplit.prefix(4).enumerated()), id: \.element.name) { index, item in
                    let pct = total > 0 ? Int(round(Double(item.count) / Double(total) * 100)) : 0
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(splitGradient(for: index))
                            .frame(width: 10, height: 10)
                        Text(item.name.capitalized)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(GQColors.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(pct)%")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(GQColors.textTertiary)
                    }
                }
            }
        }
    }

    private func splitGradient(for index: Int) -> LinearGradient {
        let gradients: [LinearGradient] = [
            LinearGradient(colors: [GQColors.deepBlue, GQColors.vividPurple], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [GQColors.vividPurple, GQColors.coralRed], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [GQColors.cyanSpark, GQColors.deepBlue], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [GQColors.sunsetOrange, GQColors.coralRed], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [GQColors.success, GQColors.cyanSpark], startPoint: .topLeading, endPoint: .bottomTrailing),
            LinearGradient(colors: [GQColors.deepBlue, GQColors.cyanSpark], startPoint: .topLeading, endPoint: .bottomTrailing),
        ]
        return gradients[index % gradients.count]
    }

    // MARK: - Body Progress

    private var bodyProgressCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Body")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Spacer()
                if latestWeight != nil {
                    NavigationLink {
                        BodyMeasurementsView(profile: profile)
                    } label: {
                        HStack(spacing: 3) {
                            Text("Details")
                                .font(.system(size: 10))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundColor(GQColors.textTertiary)
                    }
                }
            }

            if weightMeasurements.isEmpty {
                emptyState(icon: "scalemass", text: "No data")
            } else {
                bodyContent
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .homeSocialCard(cornerRadius: 14)
    }

    @ViewBuilder
    private var bodyContent: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(GQGradients.primary.opacity(0.06))
                    .frame(width: 95, height: 95)
                    .blur(radius: 10)

                Circle()
                    .stroke(GQColors.adaptiveOverlay(0.04), lineWidth: 7)
                    .frame(width: 84, height: 84)
                Circle()
                    .trim(from: 0, to: 0.75 * animateRings)
                    .stroke(GQGradients.primary, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 84, height: 84)

                VStack(spacing: 0) {
                    if let w = latestWeight {
                        Text(String(format: "%.0f", w))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(GQColors.textPrimary)
                        Text("lbs")
                            .font(.system(size: 10))
                            .foregroundColor(GQColors.textTertiary)
                    }
                }
            }

            if let change = weightChange {
                HStack(spacing: 4) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%.1f lbs", abs(change)))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(change >= 0 ? GQColors.success : GQColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill((change >= 0 ? GQColors.success : GQColors.textSecondary).opacity(0.1))
                )
            }

            if weightMeasurements.count >= 2 {
                Chart(weightMeasurements.suffix(10), id: \.id) { m in
                    AreaMark(
                        x: .value("Date", m.date),
                        y: .value("Weight", m.value)
                    )
                    .foregroundStyle(GQGradients.primary.opacity(0.1))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", m.date),
                        y: .value("Weight", m.value)
                    )
                    .foregroundStyle(GQGradients.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 40)
            }
        }
    }

    // MARK: - PRs Card

    private var prsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(GQGradients.primary)
                Text("Recent PRs")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Spacer()
                Text("\(totalPRs) total")
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
            }

            VStack(spacing: 0) {
                ForEach(Array(recentPRs.enumerated()), id: \.element.id) { index, pr in
                    HStack(spacing: 12) {
                        // Rank circle
                        ZStack {
                            Circle()
                                .fill(GQGradients.primary.opacity(index == 0 ? 0.15 : 0.06))
                                .frame(width: 34, height: 34)
                            Text("\(index + 1)")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(index == 0 ? AnyShapeStyle(GQGradients.primary) : AnyShapeStyle(GQColors.textTertiary))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(pr.exerciseName)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(GQColors.textPrimary)
                                .lineLimit(1)
                            Text(pr.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 11))
                                .foregroundColor(GQColors.textTertiary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.0f lbs", pr.newValue))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(GQColors.textPrimary)
                            if let delta = pr.deltaDisplay {
                                Text(delta)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(GQColors.success)
                            }
                        }
                    }
                    .padding(.vertical, 8)

                    if index < recentPRs.count - 1 {
                        Divider().overlay(GQColors.adaptiveOverlay(0.04))
                    }
                }
            }
        }
        .padding(16)
        .homeSocialCard(cornerRadius: 14)
    }

    // MARK: - Nutrition (7-day calories bar chart)

    private var nutritionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(GQGradients.primary)
                Text("Nutrition")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Spacer()
                if profile.dailyCalorieGoal > 0 {
                    Text("\(profile.dailyCalorieGoal) cal goal")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(GQColors.textTertiary)
                }
            }

            nutritionBars
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeSocialCard(cornerRadius: 14)
    }

    private var nutritionWeeklyTotals: [(date: Date, cal: Int)] {
        let service = NutritionService.shared
        service.configure(modelContext: modelContext)
        let cal = Calendar.current
        return (0..<7).reversed().compactMap { offset -> (date: Date, cal: Int)? in
            guard let start = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: Date())) else { return nil }
            guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
            let meals = service.getMeals(userId: profile.id, from: start, to: end)
            let total = meals.reduce(0) { $0 + ($1.estimatedCalories ?? 0) }
            return (start, total)
        }
    }

    /// Single-letter weekday for the mini bar chart labels.
    private func weekdayInitial(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE"
        return String(df.string(from: date).prefix(1))
    }

    @ViewBuilder
    private var nutritionBars: some View {
        let totals = nutritionWeeklyTotals
        let anyLogged = totals.contains { $0.cal > 0 }
        if !anyLogged {
            emptyState(icon: "flame", text: "No meals logged yet")
        } else {
            let maxCal = max(totals.map(\.cal).max() ?? 0, profile.dailyCalorieGoal > 0 ? profile.dailyCalorieGoal : 2000)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(totals.enumerated()), id: \.offset) { _, entry in
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(GQColors.adaptiveOverlay(0.05))
                                .frame(height: 70)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(GQGradients.primary)
                                .frame(height: maxCal > 0 ? 70 * CGFloat(entry.cal) / CGFloat(maxCal) : 0)
                        }
                        Text(weekdayInitial(entry.date))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(GQColors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Exercise Trends

    private var exerciseTrendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 13))
                    .foregroundStyle(GQGradients.primary)
                Text("Exercise Trends")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
            }

            if allExerciseNames.isEmpty {
                emptyState(icon: "chart.xyaxis.line", text: "Log exercises to see progression")
            } else {
                exercisePillsAndChart
            }
        }
        .padding(16)
        .homeSocialCard(cornerRadius: 14)
    }

    @ViewBuilder
    private var exercisePillsAndChart: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allExerciseNames.prefix(8), id: \.self) { name in
                    let isSelected = selectedExerciseName == name
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedExerciseName = name
                            showingExerciseTrend = true
                        }
                    } label: {
                        Text(name)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(isSelected ? .white : GQColors.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isSelected ?
                                AnyShapeStyle(GQGradients.primary) :
                                AnyShapeStyle(GQColors.adaptiveOverlay(0.05))
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            if selectedExerciseName.isEmpty, let first = allExerciseNames.first {
                selectedExerciseName = first
                showingExerciseTrend = true
            }
        }

        if showingExerciseTrend && !selectedExerciseName.isEmpty {
            ExerciseTrendChart(exerciseName: selectedExerciseName, workouts: Array(validWorkouts))
                .transition(.opacity)
        }
    }

    // MARK: - Goals Section

    @ViewBuilder
    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "target")
                    .font(.system(size: 13))
                    .foregroundStyle(GQGradients.primary)
                Text("Goals")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                Spacer()
                Button {
                    showingAddGoal = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(GQGradients.primary)
                }
                .buttonStyle(.plain)
            }

            if activeGoals.isEmpty && achievedGoals.isEmpty {
                emptyState(icon: "target", text: "Set a goal to track your progress")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(activeGoals.enumerated()), id: \.element.id) { index, goal in
                        goalRow(goal: goal)
                        if index < activeGoals.count - 1 || !achievedGoals.isEmpty {
                            Divider().overlay(GQColors.adaptiveOverlay(0.04))
                        }
                    }
                    ForEach(Array(achievedGoals.prefix(3).enumerated()), id: \.element.id) { index, goal in
                        goalRow(goal: goal)
                        if index < min(achievedGoals.count, 3) - 1 {
                            Divider().overlay(GQColors.adaptiveOverlay(0.04))
                        }
                    }
                }
            }
        }
        .padding(16)
        .homeSocialCard(cornerRadius: 14)
    }

    private func goalRow(goal: UserGoal) -> some View {
        let progress = goalProgress(for: goal)
        let fraction = goal.targetWeight > 0 ? min(progress / goal.targetWeight, 1.0) : 0

        return HStack(spacing: 12) {
            // Mini progress ring
            ZStack {
                Circle()
                    .stroke(GQColors.adaptiveOverlay(0.06), lineWidth: 4)
                    .frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: CGFloat(fraction) * animateRings)
                    .stroke(
                        goal.isAchieved ? LinearGradient(colors: [GQColors.success, GQColors.cyanSpark], startPoint: .topLeading, endPoint: .bottomTrailing) : GQGradients.primary,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 36, height: 36)

                if goal.isAchieved {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(GQColors.success)
                } else {
                    Text("\(Int(fraction * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(GQColors.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(goal.exerciseName ?? "Body Weight")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
                if goal.isExerciseGoal, let reps = goal.targetReps {
                    Text("\(Int(goal.targetWeight)) lbs x \(reps)")
                        .font(.system(size: 11))
                        .foregroundColor(GQColors.textTertiary)
                } else {
                    Text("\(Int(goal.targetWeight)) lbs")
                        .font(.system(size: 11))
                        .foregroundColor(GQColors.textTertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(progress)) lbs")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(GQColors.textPrimary)
                Text("current")
                    .font(.system(size: 10))
                    .foregroundColor(GQColors.textTertiary)
            }
        }
        .padding(.vertical, 8)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                modelContext.delete(goal)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func goalProgress(for goal: UserGoal) -> Double {
        if goal.isExerciseGoal {
            guard let name = goal.exerciseName else { return 0 }
            var bestWeight: Double = 0
            for w in workouts {
                for ex in w.exercises where ex.name == name {
                    for s in ex.sets {
                        if let targetReps = goal.targetReps {
                            if s.reps >= targetReps {
                                bestWeight = max(bestWeight, s.weight)
                            }
                        } else {
                            bestWeight = max(bestWeight, s.weight)
                        }
                    }
                }
            }
            if bestWeight >= goal.targetWeight && !goal.isAchieved {
                goal.achievedAt = Date()
            }
            return bestWeight
        } else {
            return latestWeight ?? 0
        }
    }

    // MARK: - Helpers

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(GQColors.textTertiary.opacity(0.4))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(GQColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Exercise Trend Chart

struct ExerciseTrendChart: View {
    let exerciseName: String
    let workouts: [Workout]

    private var dataPoints: [(date: Date, weight: Double)] {
        var points: [(Date, Double)] = []
        for w in workouts.reversed() {
            for ex in w.exercises where ex.name == exerciseName {
                let maxWeight = ex.sets.map { $0.weight }.max() ?? 0
                if maxWeight > 0 { points.append((w.date, maxWeight)) }
            }
        }
        return points
    }

    var body: some View {
        if dataPoints.count < 2 {
            Text("Need at least 2 sessions")
                .font(.system(size: 12))
                .foregroundColor(GQColors.textTertiary)
                .padding(.vertical, 10)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                // Best weight badge
                if let best = dataPoints.map(\.weight).max() {
                    HStack(spacing: 4) {
                        Text("Best")
                            .font(.system(size: 10))
                            .foregroundColor(GQColors.textTertiary)
                        Text("\(Int(best)) lbs")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(GQGradients.primary)
                    }
                }

                Chart(dataPoints, id: \.date) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.weight)
                    )
                    .foregroundStyle(GQGradients.primary.opacity(0.08))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.weight)
                    )
                    .foregroundStyle(GQGradients.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("Weight", point.weight)
                    )
                    .foregroundStyle(GQGradients.primary)
                    .symbolSize(20)
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v))")
                                    .font(.system(size: 10))
                                    .foregroundColor(GQColors.textTertiary)
                            }
                        }
                        AxisGridLine()
                            .foregroundStyle(GQColors.adaptiveOverlay(0.04))
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 140)
            }
        }
    }
}

// MARK: - Add Goal Sheet

struct AddGoalSheet: View {
    let profile: UserProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var goalType: GoalType = .exercise
    @State private var exerciseName = ""
    @State private var targetWeight = ""
    @State private var targetReps = ""
    @State private var searchText = ""

    enum GoalType: String, CaseIterable {
        case exercise = "Exercise"
        case bodyweight = "Body Weight"
    }

    private var filteredExercises: [String] {
        let all = ExtendedExerciseDatabase.exercises.map(\.name)
        if searchText.isEmpty { return Array(all.prefix(20)) }
        return all.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    private var canSave: Bool {
        guard let weight = Double(targetWeight), weight > 0 else { return false }
        if goalType == .exercise {
            return !exerciseName.isEmpty
        }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Goal type picker
                    HStack(spacing: 0) {
                        ForEach(GoalType.allCases, id: \.self) { type in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { goalType = type }
                            } label: {
                                Text(type.rawValue)
                                    .font(.system(size: 14, weight: goalType == type ? .semibold : .medium))
                                    .foregroundColor(goalType == type ? .white : GQColors.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        goalType == type ?
                                        AnyShapeStyle(GQGradients.primary) :
                                        AnyShapeStyle(Color.clear)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(GQColors.adaptiveOverlay(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    if goalType == .exercise {
                        exerciseSelector
                    }

                    // Target weight
                    VStack(alignment: .leading, spacing: 8) {
                        Text(goalType == .bodyweight ? "Target Weight" : "Target Weight (lbs)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(GQColors.textSecondary)
                        TextField("e.g. 225", text: $targetWeight)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .padding(14)
                            .background(GQColors.adaptiveOverlay(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(GQColors.borderDefault, lineWidth: 1)
                            )
                    }

                    if goalType == .exercise {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Target Reps")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(GQColors.textSecondary)
                            TextField("e.g. 5", text: $targetReps)
                                .keyboardType(.numberPad)
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .padding(14)
                                .background(GQColors.adaptiveOverlay(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(GQColors.borderDefault, lineWidth: 1)
                                )
                        }
                    }

                    // Save button
                    Button {
                        saveGoal()
                    } label: {
                        Text("Set Goal")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(canSave ? AnyShapeStyle(GQGradients.primary) : AnyShapeStyle(GQColors.adaptiveOverlay(0.1)))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                }
                .padding(20)
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GQColors.textSecondary)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var exerciseSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exercise")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(GQColors.textSecondary)

            if !exerciseName.isEmpty {
                HStack {
                    Text(exerciseName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(GQColors.textPrimary)
                    Spacer()
                    Button {
                        exerciseName = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(GQColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(GQColors.adaptiveOverlay(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(GQGradients.primary.opacity(0.3), lineWidth: 1)
                )
            } else {
                TextField("Search exercises...", text: $searchText)
                    .font(.system(size: 15))
                    .padding(14)
                    .background(GQColors.adaptiveOverlay(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(GQColors.borderDefault, lineWidth: 1)
                    )

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredExercises.prefix(8), id: \.self) { name in
                            Button {
                                exerciseName = name
                                searchText = ""
                            } label: {
                                HStack {
                                    Text(name)
                                        .font(.system(size: 14))
                                        .foregroundColor(GQColors.textPrimary)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(GQColors.adaptiveOverlay(0.04))
                        }
                    }
                }
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(GQColors.borderDefault, lineWidth: 1)
                )
            }
        }
    }

    private func saveGoal() {
        guard let weight = Double(targetWeight), weight > 0 else { return }
        let reps = Int(targetReps)

        let goal = UserGoal(
            userId: profile.id,
            type: goalType == .exercise ? "exercise" : "bodyweight",
            exerciseName: goalType == .exercise ? exerciseName : nil,
            targetWeight: weight,
            targetReps: goalType == .exercise ? reps : nil
        )

        modelContext.insert(goal)
        dismiss()
    }
}
