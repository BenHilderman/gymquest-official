//
//  AliveReactions.swift
//  GymQuest
//
//  Phase 2 of the Alive release: two-way reactions + inbox + auto-react.
//  Surfaces:
//   - Long-press any friend avatar (avatars carrying .presenceRing) →
//     ReactionPaletteSheet with 6 emoji + voice + photo + stat sticker.
//   - ReactionInbox card on Today after own workout ends, listing every
//     reaction received during the session window.
//   - JustFinishedCard on Today for 10 min when a friend transitions to
//     .finishedRecently.
//   - AutoReactStore: per-friend toggle, auto-fires 🔥 when their status
//     transitions to .training.
//

import SwiftUI
import SwiftData
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - UserDefaults stores

/// Per-friend auto-fire 🔥 toggle. Kept in UserDefaults so we don't
/// over-engineer a SwiftData row for a Set of UUIDs.
enum AutoReactStore {
    private static let key = "alive.autoReact.userIds"

    static func load() -> Set<UUID> {
        let strings = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(strings.compactMap(UUID.init(uuidString:)))
    }

    static func contains(_ id: UUID) -> Bool { load().contains(id) }

    static func toggle(_ id: UUID) {
        var current = load()
        if current.contains(id) { current.remove(id) } else { current.insert(id) }
        UserDefaults.standard.set(current.map { $0.uuidString }, forKey: key)
    }
}

/// Sessions the user opted out of presence broadcasting for. Keyed by the
/// session start timestamp so re-entering a workout always re-asks.
enum GhostSessionStore {
    private static let key = "alive.ghostSessions"

    static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func mark(sessionId: String) {
        var current = load()
        current.insert(sessionId)
        UserDefaults.standard.set(Array(current), forKey: key)
    }

    static func contains(sessionId: String) -> Bool { load().contains(sessionId) }
}

/// Master per-app toggle for ever sharing location at all. Default off —
/// privacy fail-closed. The per-session dialog still asks each time.
enum LocationOptInStore {
    private static let key = "alive.locationOptIn"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// MARK: - Reaction palette sheet

/// Bottom sheet shown when the user long-presses a friend avatar. Six
/// quick-emoji + voice/photo/stat. Sends a Reaction tied to the friend's
/// current session window (their `PresenceState.startedAt`).
struct ReactionPaletteSheet: View {
    let toUserId: UUID
    let toUserName: String
    let recipientStartedAt: Date
    let fromUserId: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private static let quickEmoji: [String] = ["🔥", "💪", "👀", "⚡️", "✋", "🤝"]
    @State private var voiceRecorder = VoiceRecorderState()
    @State private var showCamera: Bool = false
    @State private var capturedPhoto: Data? = nil
    @State private var didSend: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            Capsule().fill(GQColors.borderDefault).frame(width: 36, height: 4).padding(.top, 8)

            Text("Send to \(toUserName)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(GQColors.textSecondary)

            // 6-emoji grid
            HStack(spacing: 8) {
                ForEach(Self.quickEmoji, id: \.self) { emoji in
                    Button {
                        send(kind: "fire", emoji: emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 30))
                            .frame(width: 48, height: 48)
                            .background(
                                Circle().fill(GQColors.surfaceBase)
                            )
                            .overlay(Circle().stroke(GQColors.borderDefault, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Action row: voice / photo / stat
            HStack(spacing: 10) {
                voiceButton
                photoButton
                statButton
            }
            .padding(.top, 4)

            if didSend {
                Text("Sent ✓")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AlivePresence.green)
                    .transition(.opacity)
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .background(GQColors.background)
        .sheet(isPresented: $showCamera) {
            ReactionPhotoCaptureSheet { data in
                capturedPhoto = data
                showCamera = false
                if let data {
                    send(kind: "photo", photo: data)
                }
            }
        }
    }

    @ViewBuilder
    private var voiceButton: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(voiceRecorder.isRecording ? AlivePresence.red.opacity(0.85) : GQColors.surfaceBase)
                    .frame(width: 56, height: 56)
                    .overlay(Circle().stroke(GQColors.borderDefault, lineWidth: 0.5))
                Image(systemName: voiceRecorder.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(voiceRecorder.isRecording ? .white : GQColors.textPrimary)
            }
            .scaleEffect(voiceRecorder.isRecording ? 1.08 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: voiceRecorder.isRecording)
            .gesture(
                LongPressGesture(minimumDuration: 0.1)
                    .onChanged { _ in voiceRecorder.start() }
                    .sequenced(before: DragGesture(minimumDistance: 0))
                    .onEnded { _ in
                        if let data = voiceRecorder.stop() {
                            send(kind: "voice", voice: data)
                        }
                    }
            )
            Text(voiceRecorder.isRecording ? "\(voiceRecorder.elapsedSeconds)s" : "Hold")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(GQColors.textTertiary)
                .frame(width: 56)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var photoButton: some View {
        Button {
            showCamera = true
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(GQColors.surfaceBase).frame(width: 56, height: 56)
                        .overlay(Circle().stroke(GQColors.borderDefault, lineWidth: 0.5))
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(GQColors.textPrimary)
                }
                Text("Selfie")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(GQColors.textTertiary)
                    .frame(width: 56)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var statButton: some View {
        Button {
            send(kind: "stat", stat: autoStatText())
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(GQColors.surfaceBase).frame(width: 56, height: 56)
                        .overlay(Circle().stroke(GQColors.borderDefault, lineWidth: 0.5))
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(GQGradients.primary)
                }
                Text("Stat")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(GQColors.textTertiary)
                    .frame(width: 56)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    /// Auto-generate a stat sticker text. Phase 2 stub: a generic motivational
    /// line. Phase 4 will replace with a per-user PR/volume comparison.
    private func autoStatText() -> String {
        let lines = [
            "+5 lbs vs my last bench day",
            "3rd lift this week — pace yours",
            "Going to match you today",
            "Up 12 lbs since last month"
        ]
        return lines.randomElement() ?? lines[0]
    }

    private func send(
        kind: String,
        emoji: String? = nil,
        voice: Data? = nil,
        photo: Data? = nil,
        stat: String? = nil
    ) {
        let reaction = LiveReaction(
            fromUserId: fromUserId,
            toUserId: toUserId,
            sessionStartedAt: recipientStartedAt,
            kind: kind,
            emoji: emoji,
            voiceData: voice,
            photoData: photo,
            statText: stat
        )
        modelContext.insert(reaction)
        try? modelContext.save()
        // v4.3 §9 — distinct haptic patterns per reaction kind so the
        // sender feels the same shape the receiver will.
        if FeatureFlags.shared.coliftV43Enabled {
            let mapped: ReactionKind = (kind == "voice") ? .voice
                : (kind == "photo") ? .photo : .emoji
            ReactionHapticPlayer.play(mapped)
        } else {
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { didSend = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            dismiss()
        }
    }
}

// MARK: - Voice recorder

private final class VoiceRecorderState: ObservableObject {
    @Published var isRecording: Bool = false
    @Published var elapsedSeconds: Int = 0
    private var recorder: AVAudioRecorder?
    private var startTime: Date?
    private var timer: Timer?
    private var url: URL?

    func start() {
        guard !isRecording else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("alive-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.record(forDuration: 10)
            self.recorder = r
            self.url = url
            self.startTime = Date()
            self.isRecording = true
            self.elapsedSeconds = 0
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self, let started = self.startTime else { return }
                self.elapsedSeconds = max(0, Int(Date().timeIntervalSince(started)))
                if self.elapsedSeconds >= 10 { _ = self.stop() }
            }
        } catch {
            recorder = nil
            isRecording = false
        }
    }

    func stop() -> Data? {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        isRecording = false
        let data: Data?
        if let url, let read = try? Data(contentsOf: url) { data = read } else { data = nil }
        recorder = nil
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
        return data
    }
}

// MARK: - Photo capture

#if canImport(UIKit)
struct ReactionPhotoCaptureSheet: UIViewControllerRepresentable {
    let onCapture: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        if picker.sourceType == .camera { picker.cameraDevice = .front }
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCapture: (Data?) -> Void
        init(onCapture: @escaping (Data?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let img = info[.originalImage] as? UIImage
            picker.dismiss(animated: true)
            onCapture(img?.jpegData(compressionQuality: 0.7))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            onCapture(nil)
        }
    }
}
#else
struct ReactionPhotoCaptureSheet: View {
    let onCapture: (Data?) -> Void
    var body: some View {
        Color.clear.onAppear { onCapture(nil) }
    }
}
#endif

// MARK: - Long-press hook for any avatar

/// Attach to any friend-avatar view to bring up the reaction palette.
/// Reads the recipient's `PresenceState.startedAt` so the reaction is
/// scoped to the right session window.
struct ReactionLongPressModifier: ViewModifier {
    let toUserId: UUID
    let toUserName: String
    let fromUserId: UUID
    let fromUserName: String
    @Environment(\.presenceLookup) private var lookup
    @State private var showSheet: Bool = false

    func body(content: Content) -> some View {
        content
            // simultaneousGesture so long-press fires even when an enclosing
            // Button (e.g. Today's friendsNowStrip wraps every avatar in one
            // outer Button for the tap-to-Friends behavior) would otherwise
            // consume the gesture.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        showSheet = true
                    }
            )
            .sheet(isPresented: $showSheet) {
                ReactionPaletteSheet(
                    toUserId: toUserId,
                    toUserName: toUserName,
                    recipientStartedAt: lookup(toUserId)?.startedAt ?? Date(),
                    fromUserId: fromUserId
                )
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.hidden)
            }
    }
}

extension View {
    /// Long-press to reveal the reaction palette aimed at this friend.
    func reactionTarget(to userId: UUID, name: String, from selfId: UUID, selfName: String = "") -> some View {
        modifier(ReactionLongPressModifier(toUserId: userId, toUserName: name, fromUserId: selfId, fromUserName: selfName))
    }
}

// MARK: - Reaction inbox card

/// Card shown on Today after own workout ends, listing reactions
/// received during the session window. Marks all reactions as
/// `seenByRecipient = true` on dismiss.
struct ReactionInboxCard: View {
    let reactions: [LiveReaction]
    let nameLookup: (UUID) -> String
    var onClear: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "tray.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GQGradients.primary)
                Text("\(reactions.count) reaction\(reactions.count == 1 ? "" : "s") while you trained")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.4)
                    .foregroundColor(GQColors.textPrimary)
                Spacer()
                Button("Clear") {
                    onClear()
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(GQGradients.primary)
            }

            VStack(spacing: 6) {
                ForEach(reactions.prefix(5)) { r in
                    reactionRow(r)
                }
                if reactions.count > 5 {
                    Text("+ \(reactions.count - 5) more")
                        .font(.system(size: 11))
                        .foregroundColor(GQColors.textTertiary)
                }
            }
        }
        .padding(14)
        .homeSocialCard(cornerRadius: 14)
    }

    @ViewBuilder
    private func reactionRow(_ r: LiveReaction) -> some View {
        HStack(spacing: 10) {
            switch r.kind {
            case "voice":
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(GQGradients.primary)
                Text("\(nameLookup(r.fromUserId)) sent a voice note")
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textPrimary)
            case "photo":
                if let data = r.photoData, let img = uiImage(from: data) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Text("\(nameLookup(r.fromUserId)) sent a selfie")
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textPrimary)
            case "stat":
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(GQGradients.primary)
                Text("\(nameLookup(r.fromUserId)) · \(r.statText ?? "")")
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textPrimary)
                    .lineLimit(1)
            default:
                Text(r.emoji ?? "🔥")
                    .font(.system(size: 18))
                Text("\(nameLookup(r.fromUserId))")
                    .font(.system(size: 13))
                    .foregroundColor(GQColors.textPrimary)
            }
            Spacer()
            Text(timeAgo(r.timestamp))
                .font(.system(size: 11))
                .foregroundColor(GQColors.textTertiary)
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let secs = Int(Date().timeIntervalSince(date))
        if secs < 60 { return "just now" }
        if secs < 3600 { return "\(secs / 60)m" }
        return "\(secs / 3600)h"
    }

    #if canImport(UIKit)
    private func uiImage(from data: Data) -> UIImage? { UIImage(data: data) }
    #else
    private func uiImage(from data: Data) -> UIImage? { nil }
    #endif
}

// MARK: - Just-finished card

/// Shown on Today for 10 min after a followed friend transitions to
/// `.finishedRecently`. One-tap reaction strip. Auto-dismisses past 10 min.
struct JustFinishedCard: View {
    let userId: UUID
    let userName: String
    let workoutType: String?
    let finishedAt: Date
    let fromUserId: UUID

    @Environment(\.modelContext) private var modelContext
    private static let quickEmoji: [String] = ["🔥", "💪", "👀", "⚡️", "✋"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AlivePresence.green)
                    .frame(width: 8, height: 8)
                Text("\(userName) just finished")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(GQColors.textPrimary)
                if let type = workoutType, !type.isEmpty {
                    Text("· \(type)")
                        .font(.system(size: 12))
                        .foregroundColor(GQColors.textSecondary)
                }
                Spacer()
                Text(timeAgo)
                    .font(.system(size: 11))
                    .foregroundColor(GQColors.textTertiary)
            }
            HStack(spacing: 8) {
                ForEach(Self.quickEmoji, id: \.self) { e in
                    Button {
                        send(emoji: e)
                    } label: {
                        Text(e)
                            .font(.system(size: 22))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(GQColors.surfaceBase))
                            .overlay(Circle().stroke(GQColors.borderDefault, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .homeSocialCard(cornerRadius: 14)
    }

    private var timeAgo: String {
        let secs = Int(Date().timeIntervalSince(finishedAt))
        if secs < 60 { return "just now" }
        return "\(secs / 60)m ago"
    }

    private func send(emoji: String) {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        let r = LiveReaction(
            fromUserId: fromUserId,
            toUserId: userId,
            sessionStartedAt: finishedAt,
            kind: "fire",
            emoji: emoji
        )
        modelContext.insert(r)
        try? modelContext.save()
    }
}

// MARK: - Auto-react service

/// Watches PresenceState transitions and fires a 🔥 reaction when a friend
/// the user opted into auto-react begins training. Idempotent per session
/// (only one auto-fire per friend per `startedAt`).
@MainActor
enum AutoReactService {
    private static var firedFor: Set<String> = []

    static func processIfNeeded(
        states: [UserPresenceState],
        selfId: UUID,
        in modelContext: ModelContext
    ) {
        let opted = AutoReactStore.load()
        guard !opted.isEmpty else { return }
        for state in states where opted.contains(state.userId) {
            guard state.status == .training, let started = state.startedAt else { continue }
            let key = "\(state.userId.uuidString)-\(Int(started.timeIntervalSince1970))"
            guard !firedFor.contains(key) else { continue }
            firedFor.insert(key)
            let r = LiveReaction(
                fromUserId: selfId,
                toUserId: state.userId,
                sessionStartedAt: started,
                kind: "fire",
                emoji: "🔥"
            )
            modelContext.insert(r)
        }
        try? modelContext.save()
    }
}
