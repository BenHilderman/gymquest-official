// Day-of-Week Ritual card — design v4.3 §4A Slot 5.
// Predictable rotation: Mon goal / Tue tip / Wed mid-week / Thu Fri planning /
// Fri weekend / Sat events / Sun crew recap.

import SwiftUI

enum DayOfWeekRitualKind: String, Identifiable {
    case mondayGoal
    case tuesdayTip
    case wednesdayCheckIn
    case thursdayFridayPlan
    case fridayWeekend
    case saturdayEvents
    case sundayCrewRecap

    var id: String { rawValue }

    static func current(now: Date = .init()) -> DayOfWeekRitualKind {
        let cal = Calendar(identifier: .gregorian)
        let weekday = cal.component(.weekday, from: now) // 1 Sun ... 7 Sat
        switch weekday {
        case 1: return .sundayCrewRecap
        case 2: return .mondayGoal
        case 3: return .tuesdayTip
        case 4: return .wednesdayCheckIn
        case 5: return .thursdayFridayPlan
        case 6: return .fridayWeekend
        case 7: return .saturdayEvents
        default: return .mondayGoal
        }
    }

    var headline: String {
        switch self {
        case .mondayGoal: return "this week's goal"
        case .tuesdayTip: return "tip of the day"
        case .wednesdayCheckIn: return "mid-week check-in"
        case .thursdayFridayPlan: return "who's training friday?"
        case .fridayWeekend: return "train this weekend?"
        case .saturdayEvents: return "weekend crew events"
        case .sundayCrewRecap: return "crew recap"
        }
    }

    var subline: String {
        switch self {
        case .mondayGoal: return "set your week"
        case .tuesdayTip: return "one move you'll use today"
        case .wednesdayCheckIn: return "how's the week going?"
        case .thursdayFridayPlan: return "see who's lifting tomorrow"
        case .fridayWeekend: return "lock in your saturday lift"
        case .saturdayEvents: return "what's happening near you"
        case .sundayCrewRecap: return "your crew's week in 30s"
        }
    }

    var icon: String {
        switch self {
        case .mondayGoal: return "target"
        case .tuesdayTip: return "lightbulb.fill"
        case .wednesdayCheckIn: return "chart.line.uptrend.xyaxis"
        case .thursdayFridayPlan: return "person.2.wave.2.fill"
        case .fridayWeekend: return "calendar.badge.plus"
        case .saturdayEvents: return "mappin.and.ellipse"
        case .sundayCrewRecap: return "sparkles"
        }
    }
}

struct DayOfWeekRitualCard: View {
    var kind: DayOfWeekRitualKind = .current()
    var onTap: (() -> Void)?

    var body: some View {
        Button {
            onTap?()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: kind.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(LinearGradient(
                        colors: [.purple.opacity(0.65), .blue.opacity(0.65)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )))

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.headline)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(kind.subline)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
        )
    }
}
