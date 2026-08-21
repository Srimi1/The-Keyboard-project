import Foundation

/// Reads this process's `phys_footprint` — the figure jetsam uses when it kills
/// keyboard extensions at roughly 60 MB, silently and with no crash log (C-10).
///
/// Instruments cannot easily attach to a keyboard extension running inside another
/// app's process, so the keyboard reports its own footprint instead. The project
/// budget is 40 MB steady state (CLAUDE.md invariant 5).
enum MemoryReporter {

    static func physFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }

        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }

    static func physFootprintMB() -> Double? {
        guard let bytes = physFootprintBytes() else { return nil }
        return Double(bytes) / (1024 * 1024)
    }

    /// Budget from CLAUDE.md invariant 5. Anything at or above this is a milestone blocker.
    static let budgetMB: Double = 40

    /// Observed jetsam range for keyboard extensions (C-10). Not a documented number.
    static let observedJetsamCeilingMB: Double = 60

    enum Verdict: String {
        case withinBudget = "within budget"
        case overBudget = "OVER 40 MB BUDGET"
        case critical = "CRITICAL — near jetsam ceiling"
    }

    static func verdict(forMB mb: Double) -> Verdict {
        if mb >= observedJetsamCeilingMB * 0.8 { return .critical }
        if mb > budgetMB { return .overBudget }
        return .withinBudget
    }
}
