// Story Composer — design v4.3 §3C posting.
// Modes: photo / video (max 15s) / text / workout share. Sticker pack + audience picker.

import SwiftUI

struct StoryComposerView: View {
    @State private var mode: StoryKind = .photo
    @State private var textBody: String = ""
    @State private var audience: PostAudience = .friends
    @State private var stickers: [StorySticker] = []
    @Environment(\.dismiss) private var dismiss
    var authorId: UUID
    var onPost: (Story) -> Void = { _ in }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                modePicker
                Group {
                    switch mode {
                    case .photo: photoMode
                    case .video: videoMode
                    case .text: textMode
                    case .workoutShare: workoutShareMode
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.06)))
                .padding(.horizontal, 16)

                stickerPack
                audiencePicker
                Spacer()
                postButton
                    .padding(.horizontal, 16).padding(.bottom, 16)
            }
            .navigationTitle("new story")
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

    private var modePicker: some View {
        Picker("mode", selection: $mode) {
            ForEach(StoryKind.allCases) { k in
                Text(k.label).tag(k)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var photoMode: some View {
        VStack {
            Image(systemName: "camera.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.7))
            Text("tap to capture")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(height: 280)
    }

    @ViewBuilder
    private var videoMode: some View {
        VStack {
            Image(systemName: "video.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.7))
            Text("hold to record · max 15s")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(height: 280)
    }

    @ViewBuilder
    private var textMode: some View {
        TextField("what's on your mind?", text: $textBody, axis: .vertical)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .lineLimit(5...10)
            .frame(height: 280)
    }

    @ViewBuilder
    private var workoutShareMode: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.7))
            Text("share your last workout")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(height: 280)
    }

    private var stickerPack: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("stickers").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(StoryStickerKind.allCases) { kind in
                        Button {
                            stickers.append(StorySticker(kind: kind))
                        } label: {
                            VStack {
                                Image(systemName: stickerIcon(kind))
                                    .font(.system(size: 18))
                                Text(stickerLabel(kind))
                                    .font(.system(size: 10))
                            }
                            .frame(width: 56, height: 56)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.10)))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func stickerIcon(_ k: StoryStickerKind) -> String {
        switch k {
        case .workoutType: return "figure.run"
        case .pr: return "trophy.fill"
        case .gymName: return "mappin.circle.fill"
        case .song: return "music.note"
        case .mood: return "face.smiling"
        case .countdown: return "timer"
        case .poll: return "chart.bar.fill"
        }
    }

    private func stickerLabel(_ k: StoryStickerKind) -> String {
        switch k {
        case .workoutType: return "type"
        case .pr: return "PR"
        case .gymName: return "gym"
        case .song: return "song"
        case .mood: return "mood"
        case .countdown: return "timer"
        case .poll: return "poll"
        }
    }

    private var audiencePicker: some View {
        Picker("audience", selection: $audience) {
            ForEach(PostAudience.allCases) { a in
                Label(a.label, systemImage: a.systemIcon).tag(a)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    private var postButton: some View {
        Button {
            let story = Story(
                authorId: authorId,
                kind: mode,
                textBody: mode == .text ? textBody : nil,
                stickers: stickers,
                audience: audience
            )
            onPost(story)
            dismiss()
        } label: {
            Text("post story")
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
}
