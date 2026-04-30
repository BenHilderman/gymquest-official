// AnimatedStatNumber — content-psychology pass.
//
// Numbers ticker up from zero on appear. Familiar pattern (Strava +
// fitness apps generally) — the brain prefers *witnessing* progress to
// being told. The animation duration is short on purpose (700ms) so it
// reads as celebratory, not slow.
//
// Use as a drop-in for any post-workout stat:
//   AnimatedStatNumber(target: 12_400, format: .integer, suffix: " lb")

import SwiftUI

struct AnimatedStatNumber: View {
    let target: Double
    let format: NumberFormat
    var suffix: String = ""
    var duration: Double = 0.7
    var font: Font = .system(size: 26, weight: .bold, design: .rounded)
    var color: Color = GQColors.textPrimary

    @State private var current: Double = 0

    enum NumberFormat {
        case integer
        case oneDecimal
        case shortVolume   // 12_400 → "12.4k"

        func render(_ value: Double) -> String {
            switch self {
            case .integer:
                return "\(Int(value.rounded()))"
            case .oneDecimal:
                return String(format: "%.1f", value)
            case .shortVolume:
                if value >= 1000 {
                    return String(format: "%.1fk", value / 1000.0)
                }
                return "\(Int(value.rounded()))"
            }
        }
    }

    var body: some View {
        Text(format.render(current) + suffix)
            .font(font)
            .foregroundColor(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .onAppear {
                withAnimation(.easeOut(duration: duration)) {
                    current = target
                }
            }
            .onChange(of: target) { _, newTarget in
                current = 0
                withAnimation(.easeOut(duration: duration)) {
                    current = newTarget
                }
            }
    }
}
