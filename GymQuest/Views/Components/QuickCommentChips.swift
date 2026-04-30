// Gen-Z native quick-comment chips — design v4.3 §3B comments + §6 conversation.

import SwiftUI

struct QuickCommentChipsRow: View {
    let onSelect: (String) -> Void
    let chips: [QuickCommentChip] = QuickCommentChip.allCases

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Button {
                        onSelect(chip.rawValue)
                    } label: {
                        Text(chip.rawValue)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

struct DMOpenerChipsRow: View {
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DMOpener.allCases) { opener in
                    Button {
                        onSelect(opener.rawValue)
                    } label: {
                        Text(opener.rawValue)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

struct SmartCaptionChipsRow: View {
    @Binding var caption: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SmartCaption.allCases) { caption in
                    Button {
                        self.caption = caption.rawValue
                    } label: {
                        Text(caption.rawValue)
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(Color.white.opacity(0.10)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}
