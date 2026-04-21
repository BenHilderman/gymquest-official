import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

/// Bluetooth scale connection state machine for the AddMeasurementSheet
/// weight flow. Exposes a published state + lastWeight so the view can
/// react to readings and auto-save.
///
/// The real CoreBluetooth discovery for BLE Weight Scale profile
/// (0x181D) and vendor protocols (Withings, Renpho, Eufy) is out of
/// scope for this pass — when BluetoothScaleService is wired to a real
/// CBCentralManager the only change required here is replacing the
/// simulateReading() call with characteristic parsing. The view layer
/// already handles the state transitions end-to-end.
@MainActor
final class BluetoothScaleService: ObservableObject {
    static let shared = BluetoothScaleService()

    enum State: Equatable {
        case idle
        case scanning
        case waiting        // connected, user needs to step on
        case captured

        var title: String {
            switch self {
            case .idle:     return "Log with a Bluetooth scale"
            case .scanning: return "Looking for your scale…"
            case .waiting:  return "Step on your scale"
            case .captured: return "Weight captured"
            }
        }

        var subtitle: String {
            switch self {
            case .idle:     return "Pair a scale once — step on it to auto-log after that."
            case .scanning: return "Make sure your scale is on and nearby."
            case .waiting:  return "Holding the reading. We'll save it automatically."
            case .captured: return "Saved to your weight history."
            }
        }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastWeight: Double?

    private var cancellable: AnyCancellable?

    func startScan() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        state = .scanning
        // Simulated scan -> waiting -> captured pipeline. Replace
        // the timers with CoreBluetooth delegate callbacks when the
        // real scale integration lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.state == .scanning else { return }
            self.state = .waiting
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            guard let self, self.state == .waiting else { return }
            self.simulateReading()
        }
    }

    func stopScan() {
        state = .idle
    }

    /// Real implementation reads from the GATT weight characteristic.
    /// For now, emits a deterministic demo reading ±0.4 lb around 172.
    private func simulateReading() {
        let jitter = Double.random(in: -0.4...0.4)
        let reading = 172.0 + jitter
        lastWeight = reading
        state = .captured
    }
}
