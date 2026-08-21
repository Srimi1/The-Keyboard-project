import Foundation
import UIKit

/// Device identification, recorded alongside every diagnostics result so a verdict in
/// CONSTRAINTS.md can name the device and iOS version it was verified on.
enum DeviceInfo {

    static var osVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    /// Hardware identifier such as "iPhone16,1".
    ///
    /// On iOS `hw.machine` is the model identifier and `hw.model` is the board ID — the
    /// inverse of macOS. In the simulator `hw.machine` returns the host architecture, so the
    /// simulated device comes from CoreSimulator's environment instead.
    ///
    /// `UIDevice.current.name` is not a substitute: since iOS 16 it returns a generic string
    /// unless the app holds the user-assigned-device-name entitlement.
    static var model: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }
        return sysctlString("hw.machine") ?? UIDevice.current.model
    }

    static var isSimulator: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] != nil
    }

    static var physicalMemoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024 * 1024)
    }

    /// Plain BSD syscall — no entitlement, allowed inside an app extension.
    ///
    /// Uses a `[UInt8]` buffer rather than `[CChar]` because Swift 6.3 deprecates the array
    /// overload of `String(cString:)`.
    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }

        if let nul = buffer.firstIndex(of: 0) { buffer.removeSubrange(nul...) }
        return String(decoding: buffer, as: UTF8.self)
    }
}
