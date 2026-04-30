// ReactionHapticPlayer — design v4.3 §9.
// Distinct haptic patterns per reaction kind so the user can tell the
// difference between an emoji reaction, a voice reaction, and a photo
// reaction without looking. Plays inline via UIKit feedback generators
// so it works without the off-project `HapticManager.swift`.

import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WatchKit)
import WatchKit
#endif

@MainActor
enum ReactionHapticPlayer {
    /// Play the haptic pattern for a given reaction kind. The patterns are
    /// designed to be discriminable on both phone and Apple Watch:
    ///   - emoji: single light tap (.success notification)
    ///   - voice: medium-light double-tap (mimics speech rhythm)
    ///   - photo: heavy single thump (mimics camera shutter)
    static func play(_ kind: ReactionKind) {
        #if canImport(UIKit)
        switch kind {
        case .emoji:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .voice:
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.impactOccurred(intensity: 0.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                gen.impactOccurred(intensity: 0.6)
            }
        case .photo:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        #elseif canImport(WatchKit)
        switch kind {
        case .emoji: WKInterfaceDevice.current().play(.success)
        case .voice: WKInterfaceDevice.current().play(.click)
        case .photo: WKInterfaceDevice.current().play(.notification)
        }
        #endif
    }
}
