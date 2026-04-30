// Partner Mode invite sheet — design v4.3 §10.

import SwiftUI

struct PartnerInviteSheet: View {
    let partnerDisplayName: String
    @State private var workoutType: String = ""
    @Environment(\.dismiss) private var dismiss
    var onSend: (_ workoutType: String?) -> Void = { _ in }

    private let suggestions = ["push", "pull", "legs", "upper", "lower", "cardio"]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("lift with \(partnerDisplayName.lowercased())")
                    .font(.system(size: 22, weight: .bold))

                Text("they'll get a push with two buttons: let's go / not now. once accepted, your workouts auto-link.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("workout type (optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { type in
                            Button {
                                workoutType = type
                            } label: {
                                Text(type)
                                    .font(.system(size: 13, weight: .medium))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Capsule().fill(workoutType == type
                                        ? AnyShapeStyle(LinearGradient(colors: [.purple, .blue],
                                                                         startPoint: .leading,
                                                                         endPoint: .trailing))
                                        : AnyShapeStyle(Color.white.opacity(0.10))))
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Spacer()
                Button {
                    onSend(workoutType.isEmpty ? nil : workoutType)
                    dismiss()
                } label: {
                    Text("send invite")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 14)
                            .fill(LinearGradient(colors: [.purple, .blue],
                                                 startPoint: .leading, endPoint: .trailing)))
                        .foregroundStyle(.white)
                        .font(.headline)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .navigationTitle("partner mode")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
            }
        }
    }
}

/// Compact partner-mode header indicator for Active Workout — single small avatar
/// + their last completed set. Tap → expand to PartnerSheet (collapses with one tap).
struct PartnerActiveHeaderIndicator: View {
    let partnerDisplayName: String
    let lastSet: String?
    let avatarURL: URL?
    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                expanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom))
                        .frame(width: 22, height: 22)
                    if let url = avatarURL {
                        AsyncImage(url: url) { phase in
                            (phase.image ?? Image(systemName: "person.fill"))
                                .resizable().scaledToFill()
                        }
                        .frame(width: 22, height: 22)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.white)
                    }
                }
                if expanded {
                    Text("\(partnerDisplayName.lowercased())\(lastSet.map { " · \($0)" } ?? "")")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.12)))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}
