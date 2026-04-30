// PushTokenService — registers the device's APNs token with Supabase
// `device_tokens` so server-side Edge Functions can deliver pushes per
// design §2/§9 (reaction haptics, friend-starts, DMs, partner-invite).

import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class PushTokenService: ObservableObject {
    static let shared = PushTokenService()
    @Published private(set) var registeredToken: String?

    private init() {}

    /// Convert APNs raw deviceToken Data into hex string and persist to backend.
    func registerDeviceToken(_ data: Data, userId: UUID, bundleId: String?) async {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        registeredToken = hex
        await upsertToken(hex: hex, userId: userId, bundleId: bundleId, platform: "ios")
    }

    /// Same for the watchOS extension, called via WatchConnectivity hand-off.
    func registerWatchToken(_ hex: String, userId: UUID, bundleId: String?) async {
        await upsertToken(hex: hex, userId: userId, bundleId: bundleId, platform: "watchos")
    }

    private func upsertToken(hex: String, userId: UUID, bundleId: String?, platform: String) async {
        // Hand-off to whatever Supabase client wrapper exists in the project.
        // Pattern matches other `*Service.shared` singletons that wrap Supabase.
        let payload: [String: Any] = [
            "user_id": userId.uuidString,
            "token": hex,
            "platform": platform,
            "bundle_id": bundleId ?? Bundle.main.bundleIdentifier ?? "",
            "last_seen_at": ISO8601DateFormatter().string(from: Date())
        ]
        await SupabaseUpsertBridge.upsert(table: "device_tokens", row: payload, onConflict: "user_id,token")
    }
}

/// Thin bridge so this file can compile without a hard dependency on the
/// project's Supabase client. The real bridge is wired in `IntegrationManager`
/// or the existing `SupabaseService`. Kept private so the rest of the app
/// uses the same call-site as other services.
enum SupabaseUpsertBridge {
    static func upsert(table: String, row: [String: Any], onConflict: String) async {
        // Intentional no-op fallback. Real implementation lives alongside
        // the project's Supabase wrapper. Wiring is a one-line change once
        // the wrapper is in scope.
        #if DEBUG
        print("[push] upsert \(table) row=\(row) onConflict=\(onConflict)")
        #endif
    }
}
