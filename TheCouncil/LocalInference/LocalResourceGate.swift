import Foundation

/// Pre-flight gate for local model loads. Ensures sufficient free memory and
/// that thermal state is not throttled before we commit to loading a large
/// weight file. Per SPEC §8.2 local runs must respect memory pressure and
/// thermal budget; the 32B Qwen load needs ~20 GB headroom.
struct LocalResourceGate: Sendable {

    enum Status: Equatable, Sendable {
        case ok
        case insufficientMemory(needed: UInt64, free: UInt64)
        case thermalThrottle(ProcessInfo.ThermalState)
    }

    let freeMemoryProvider: @Sendable () -> UInt64
    let thermalStateProvider: @Sendable () -> ProcessInfo.ThermalState

    init(
        freeMemoryProvider: @escaping @Sendable () -> UInt64 = LocalResourceGate.systemFreeMemory,
        thermalStateProvider: @escaping @Sendable () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState }
    ) {
        self.freeMemoryProvider = freeMemoryProvider
        self.thermalStateProvider = thermalStateProvider
    }

    func check(minFreeBytes: UInt64) -> Status {
        let thermal = thermalStateProvider()
        if thermal == .serious || thermal == .critical {
            return .thermalThrottle(thermal)
        }
        let free = freeMemoryProvider()
        if free < minFreeBytes {
            return .insufficientMemory(needed: minFreeBytes, free: free)
        }
        return .ok
    }

    /// Free memory estimate via `host_statistics64` — counts free + inactive pages
    /// (macOS can reclaim inactive pages cheaply). Returns 0 on failure.
    static func systemFreeMemory() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { iptr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, iptr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        return (UInt64(stats.free_count) + UInt64(stats.inactive_count)) * UInt64(pageSize)
    }
}

extension ProcessInfo.ThermalState {
    var displayLabel: String {
        switch self {
        case .nominal:  return "Nominal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
}
