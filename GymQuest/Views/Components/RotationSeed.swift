// RotationSeed — session-stable index for rotating slim-line pools.
//
// Locked-spec rule (v4.3 §4 / Item H): "rotates per open, stable while
// user is on the surface." Calling `.randomElement()` re-rolls every
// SwiftUI render, which makes lines flicker as the user scrolls. Holding
// a `@State RotationSeed` per surface fixes the index for the lifetime
// of that view, and exposes `advance()` so a tap can cycle to the next
// stat without breaking the pure rotation contract.

import SwiftUI

/// Stable rotation seed for slim-line pools. Stored as `@State`, so each
/// presentation of the surface gets a fresh roll and the index survives
/// re-renders within that presentation.
struct RotationSeed {
    /// Current index into the rotation pool. Modulo'd by the consumer
    /// against the actual pool size so this stays pool-agnostic.
    var index: Int

    init() {
        // A medium-sized random seed picks a pool slot fairly across all
        // pool sizes the v4.3 surfaces use (2–10 items). Per-launch entropy
        // is the goal, not cryptographic randomness.
        self.index = Int.random(in: 0..<1024)
    }

    mutating func advance() {
        index &+= 1
    }
}
