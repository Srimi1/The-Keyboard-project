import Foundation
import UIKit

/// Device identification, recorded alongside every diagnostics result so a verdict in
/// CONSTRAINTS.md can name the device and iOS version it was verified on.
enum DeviceInfo {

    static var osVersion: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    /// Hardware identifier such as "iPhone16,1". In the simulator this returns the
    /// simulated device from the environment rather than the host Mac's architecture.
    static var model: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (Simulator)"
        }

        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else {
            return UIDevice.current.model
        }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &buffer, &size, nil, 0) == 0 else {
            return UIDevice.current.model
        }

        return String(cString: buffer)
    }

    static var isSimulator: Bool {
        ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] != nil
    }
}
