import Foundation
import Darwin

/// Reads this process's `phys_footprint` — the figure jetsam uses when it kills keyboard
/// extensions at roughly 60 MB, silently and with no crash log (C-10).
///
/// Instruments cannot easily attach to a keyboard extension running inside another app's
/// process, so the keyboard reports its own footprint instead. The project budget is 40 MB
/// steady state (CLAUDE.md invariant 5).
enum MemoryReporter {

    /// `<mach/task_info.h>` defines `TASK_VM_INFO_COUNT` as
    /// `sizeof(task_vm_info_data_t) / sizeof(natural_t)`, but Swift cannot import that macro
    /// ("structure not supported"), so it has to be recomputed. The divisor is `natural_t`
    /// per the header; the *buffer* is rebound to `integer_t` because
    /// `task_info_t == UnsafeMutablePointer<integer_t>`. Both are 4 bytes.
    private static let vmInfoCount = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
    )

    /// First struct revision containing `phys_footprint`. `task_info` reports how many ints
    /// it actually filled; below this the field is uninitialized garbage rather than an
    /// error, so the count must be checked before the value is trusted.
    private static let vmInfoRev1Count = mach_msg_type_number_t(
        (MemoryLayout<task_vm_info_data_t>.offset(of: \.phys_footprint)!
            + MemoryLayout<mach_vm_size_t>.size) / MemoryLayout<natural_t>.size
    )

    /// First struct revision containing `limit_bytes_remaining`.
    private static let vmInfoRev4Count = mach_msg_type_number_t(
        (MemoryLayout<task_vm_info_data_t>.offset(of: \.limit_bytes_remaining)!
            + MemoryLayout<UInt64>.size) / MemoryLayout<natural_t>.size
    )

    struct Reading {
        /// Bytes. What jetsam kills on, and what Xcode's memory gauge shows.
        var physFootprint: UInt64
        /// Bytes left before this process hits its own jetsam limit — the only way to learn
        /// the real ceiling on *this* device rather than guessing from reports (Q-04).
        /// nil on kernels predating rev4.
        var limitBytesRemaining: UInt64?

        var physFootprintMB: Double { Double(physFootprint) / (1024 * 1024) }

        /// The measured ceiling: what we are using plus what is left.
        var jetsamLimitMB: Double? {
            guard let remaining = limitBytesRemaining, remaining > 0 else { return nil }
            return Double(physFootprint + remaining) / (1024 * 1024)
        }
    }

    static func read() -> Reading? {
        var info = task_vm_info_data_t()
        var count = vmInfoCount

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }

        guard result == KERN_SUCCESS, count >= vmInfoRev1Count else { return nil }

        return Reading(
            physFootprint: info.phys_footprint,
            limitBytesRemaining: count >= vmInfoRev4Count && info.limit_bytes_remaining > 0
                ? info.limit_bytes_remaining
                : nil
        )
    }

    static func physFootprintMB() -> Double? {
        read()?.physFootprintMB
    }

    /// Budget from CLAUDE.md invariant 5. Anything at or above this is a milestone blocker.
    static let budgetMB: Double = 40

    /// Observed jetsam range for keyboard extensions (C-10). Not a documented number, and
    /// only a fallback — `Reading.jetsamLimitMB` is the real figure when available.
    static let observedJetsamCeilingMB: Double = 60

    enum Verdict: String {
        case withinBudget = "within budget"
        case overBudget = "OVER 40 MB BUDGET"
        case critical = "CRITICAL — near jetsam ceiling"
    }

    static func verdict(forMB mb: Double, ceilingMB: Double? = nil) -> Verdict {
        let ceiling = ceilingMB ?? observedJetsamCeilingMB
        if mb >= ceiling * 0.8 { return .critical }
        if mb > budgetMB { return .overBudget }
        return .withinBudget
    }
}
