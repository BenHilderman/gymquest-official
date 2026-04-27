//
//  ColiftActiveFriendsWidget.swift
//  ColiftWidgets
//
//  Home/lock-screen widget showing up to 4 active friend avatars. Reads
//  the snapshot the main app writes via AliveActiveFriendsBridge.
//
//  REQUIRES: AliveActiveFriendsBridge to be reachable from this target.
//  Easiest path: in Xcode, add AliveIntegrations.swift's "Target
//  Membership" to include the widget target. Alternatively, factor the
//  bridge struct out into a shared file with explicit dual membership.
//
//  For App-Group sharing across processes (the widget is its own
//  process), set up an App Group entitlement (e.g.
//  group.com.liftai.shared) in BOTH targets, and replace
//  UserDefaults.standard with UserDefaults(suiteName:) in the bridge.
//

import WidgetKit
import SwiftUI

struct ColiftActiveFriendsEntry: TimelineEntry {
    let date: Date
    let friends: [ActiveFriend]

    struct ActiveFriend: Identifiable {
        let id: UUID
        let name: String
        let initial: String
        let workoutTypeRaw: String?
    }
}

struct ColiftActiveFriendsProvider: TimelineProvider {
    func placeholder(in context: Context) -> ColiftActiveFriendsEntry {
        ColiftActiveFriendsEntry(date: Date(), friends: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (ColiftActiveFriendsEntry) -> Void) {
        completion(load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ColiftActiveFriendsEntry>) -> Void) {
        let entry = load()
        let next = Date().addingTimeInterval(60 * 5)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func load() -> ColiftActiveFriendsEntry {
        guard let snap = AliveActiveFriendsBridge.read() else {
            return ColiftActiveFriendsEntry(date: Date(), friends: [])
        }
        let mapped = snap.friends.map {
            ColiftActiveFriendsEntry.ActiveFriend(
                id: $0.id, name: $0.name, initial: $0.initial, workoutTypeRaw: $0.workoutTypeRaw
            )
        }
        return ColiftActiveFriendsEntry(date: snap.updatedAt, friends: mapped)
    }
}

struct ColiftActiveFriendsView: View {
    let entry: ColiftActiveFriendsEntry

    var body: some View {
        if entry.friends.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 28))
                    .foregroundColor(.secondary)
                Text("Nobody lifting")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("LIFTING NOW")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.0)
                    .foregroundColor(.green)
                ForEach(entry.friends.prefix(4)) { f in
                    Link(destination: URL(string: "liftai://reaction/\(f.id.uuidString)")!) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [Color(red: 0.24, green: 0.49, blue: 1.0),
                                             Color(red: 0.55, green: 0.30, blue: 0.95)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ))
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Text(f.initial)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                )
                                .overlay(
                                    Circle().stroke(Color.green, lineWidth: 1.5)
                                )
                            Text(f.name.split(separator: " ").first.map(String.init) ?? f.name)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            if let type = f.workoutTypeRaw {
                                Text("· \(type)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(8)
        }
    }
}

struct ColiftActiveFriendsWidget: Widget {
    let kind: String = "ColiftActiveFriendsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ColiftActiveFriendsProvider()) { entry in
            ColiftActiveFriendsView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Lifting Now")
        .description("See your friends mid-workout. Tap an avatar to react.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
