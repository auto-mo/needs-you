import Darwin
import Foundation

/// Exits with code 1 if the app's memory footprint passes the cap, so launchd restarts it clean.
/// A leak then shows up as a logged restart instead of a slow Mac.
enum MemoryCap {
    static let limitBytes: UInt64 = 300 * 1024 * 1024

    static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? info.phys_footprint : 0
    }

    static func check() {
        let f = footprint()
        guard f > limitBytes else { return }
        FileHandle.standardError.write(Data("Needs You: memory footprint \(f / 1_048_576) MB is over the \(limitBytes / 1_048_576) MB cap; exiting so launchd restarts it.\n".utf8))
        exit(1)
    }
}
