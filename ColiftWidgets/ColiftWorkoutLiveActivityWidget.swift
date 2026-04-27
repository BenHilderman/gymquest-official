//
//  ColiftWorkoutLiveActivityWidget.swift
//  ColiftWidgets
//
//  Lock-screen + Dynamic Island rendering for the own-workout Live
//  Activity defined by ColiftWorkoutAttributes (in the main app target).
//
//  REQUIRES: ColiftWorkoutAttributes.swift to be a member of BOTH the
//  main app target AND this widget extension target. In Xcode's File
//  Inspector, check both targets in the Target Membership section.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ColiftWorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ColiftWorkoutAttributes.self) { ctx in
            // Lock-screen / banner content.
            HStack(spacing: 14) {
                // Workout type pill
                VStack(alignment: .leading, spacing: 2) {
                    Text(ctx.attributes.customTitle ?? ctx.attributes.workoutTypeRaw)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("Lifting")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                        .tracking(0.6)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(ctx.state.setsCompleted)/\(ctx.state.totalSets)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                    Text("sets")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                }
                ElapsedTimer(startedAt: ctx.state.startedAt)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(LinearGradient(
                colors: [Color(red: 0.24, green: 0.49, blue: 1.0),
                         Color(red: 0.55, green: 0.30, blue: 0.95)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(ctx.attributes.customTitle ?? ctx.attributes.workoutTypeRaw)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(ctx.state.setsCompleted)/\(ctx.state.totalSets)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    ElapsedTimer(startedAt: ctx.state.startedAt)
                        .foregroundColor(.white.opacity(0.7))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: progress(ctx: ctx))
                        .progressViewStyle(.linear)
                        .tint(.green)
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundColor(.green)
            } compactTrailing: {
                Text("\(ctx.state.setsCompleted)/\(ctx.state.totalSets)")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "dumbbell.fill")
                    .foregroundColor(.green)
            }
        }
    }

    private func progress(ctx: ActivityViewContext<ColiftWorkoutAttributes>) -> Double {
        guard ctx.state.totalSets > 0 else { return 0 }
        return min(1, Double(ctx.state.setsCompleted) / Double(ctx.state.totalSets))
    }
}

private struct ElapsedTimer: View {
    let startedAt: Date
    var body: some View {
        Text(startedAt, style: .timer)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundColor(.white.opacity(0.85))
    }
}
