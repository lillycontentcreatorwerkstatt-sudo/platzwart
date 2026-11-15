import Darwin
import Foundation

/// Liest Speicherplatz, Arbeitsspeicher und CPU-Last des Macs – nur lesend.
final class SystemStats: ObservableObject {
    @Published var diskTotal: Int64 = 0
    @Published var diskFree: Int64 = 0
    @Published var memTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    @Published var memUsed: UInt64 = 0
    @Published var cpu: Double = 0
    /// Speicherdruck laut macOS: 1 = normal, 2 = Warnung, 4 = kritisch.
    @Published var memPressureLevel: Int = 1
    /// Anteil, der laut macOS noch verfügbar ist (0…1).
    @Published var memAvailable: Double = 1

    var diskUsedFraction: Double {
        diskTotal > 0 ? Double(diskTotal - diskFree) / Double(diskTotal) : 0
    }

    private var timer: Timer?
    private var lastTicks: (UInt32, UInt32, UInt32, UInt32)?
    private var tick = 0

    init() {
        readDisk()
        readMemory()
        readCPU()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        tick += 1
        if tick % 15 == 0 { readDisk() } // Speicherplatz ändert sich langsam: alle 30 s
        readMemory()
        readCPU()
    }

    func readDisk() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? home.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey
        ]) else { return }
        diskTotal = Int64(values.volumeTotalCapacity ?? 0)
        diskFree = values.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func readMemory() {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let page = UInt64(vm_kernel_page_size)
        let internalPages = UInt64(info.internal_page_count)
        let purgeable = UInt64(info.purgeable_count)
        let appPages = internalPages > purgeable ? internalPages - purgeable : 0
        // Wie die Aktivitätsanzeige: App-Speicher + fixierter + komprimierter Speicher
        memUsed = (appPages + UInt64(info.wire_count) + UInt64(info.compressor_page_count)) * page

        if let level = Self.sysctlInt("kern.memorystatus_vm_pressure_level") { memPressureLevel = level }
        if let free = Self.sysctlInt("kern.memorystatus_level") { memAvailable = Double(free) / 100 }
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return Int(value)
    }

    private func readCPU() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let ticks = info.cpu_ticks // (user, system, idle, nice)
        if let last = lastTicks {
            let user = Double(ticks.0 &- last.0)
            let system = Double(ticks.1 &- last.1)
            let idle = Double(ticks.2 &- last.2)
            let nice = Double(ticks.3 &- last.3)
            let total = user + system + idle + nice
            if total > 0 { cpu = (user + system + nice) / total }
        }
        lastTicks = ticks
    }
}
