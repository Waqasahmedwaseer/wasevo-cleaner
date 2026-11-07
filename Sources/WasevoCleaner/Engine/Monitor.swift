import Foundation
import AppKit
import IOKit
import IOKit.ps

// Wasevo Cleaner — System monitor (read-only): CPU, memory, swap, battery, and the apps using the most.
// The only action here is asking an app to quit normally (it can still ask you to save first).

struct CPUTicks { var user: UInt64 = 0, system: UInt64 = 0, idle: UInt64 = 0, nice: UInt64 = 0 }

func readCPUTicks() -> CPUTicks {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    let r = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) }
    }
    guard r == KERN_SUCCESS else { return CPUTicks() }
    return CPUTicks(user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1),
                    idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
}

/// CPU busy share (0…1) between two tick readings.
func cpuUsage(_ a: CPUTicks, _ b: CPUTicks) -> Double {
    let busy = Double((b.user - a.user) + (b.system - a.system) + (b.nice - a.nice))
    let all = busy + Double(b.idle - a.idle)
    return all > 0 ? busy / all : 0
}

struct MemoryInfo { let used: Int64; let total: Int64; let compressed: Int64; let swapUsed: Int64 }

/// "Memory used" the way Activity Monitor counts it: app memory + wired + compressed.
func readMemory() -> MemoryInfo {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
    let r = withUnsafeMutablePointer(to: &stats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
    }
    let page = Int64(vm_kernel_page_size)
    let total = Int64(ProcessInfo.processInfo.physicalMemory)
    var swap = xsw_usage()
    var size = MemoryLayout<xsw_usage>.size
    sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
    guard r == KERN_SUCCESS else { return MemoryInfo(used: 0, total: total, compressed: 0, swapUsed: Int64(swap.xsu_used)) }
    let app = Int64(stats.internal_page_count) - Int64(stats.purgeable_count)
    let used = (app + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
    return MemoryInfo(used: min(used, total), total: total, compressed: Int64(stats.compressor_page_count) * page,
                      swapUsed: Int64(swap.xsu_used))
}

struct BatteryInfo {
    let percent: Int
    let charging: Bool
    let onAC: Bool
    let cycles: Int?
    let health: Double?        // current full-charge capacity / design capacity
}

func readBattery() -> BatteryInfo? {
    guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
    for ps in list {
        guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
              d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
        let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0, max = d[kIOPSMaxCapacityKey] as? Int ?? 100
        var cycles: Int?, health: Double?
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if svc != 0 {
            func prop(_ k: String) -> Int? { IORegistryEntryCreateCFProperty(svc, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int }
            cycles = prop("CycleCount")
            if let design = prop("DesignCapacity"), design > 0, let full = prop("AppleRawMaxCapacity") ?? prop("MaxCapacity"), full > 100 {
                health = Double(full) / Double(design)
            }
            IOObjectRelease(svc)
        }
        return BatteryInfo(percent: max > 0 ? cur * 100 / max : cur, charging: d[kIOPSIsChargingKey] as? Bool ?? false,
                           onAC: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue, cycles: cycles, health: health)
    }
    return nil
}

struct AppUsage: Identifiable {
    var id: pid_t { pid }
    let pid: pid_t
    let name: String
    let bundleId: String
    let icon: NSImage?
    let cpu: Double        // percent of one core, summed over the app and its helpers
    let memory: Int64      // resident memory of the app and its helpers
}

/// Open apps (the ones in your Dock) with the CPU and memory they and their helper processes use.
func heavyApps() -> [AppUsage] {
    var rows: [(cpu: Double, rss: Int64, path: String)] = []
    for line in sh("ps -axo pcpu=,rss=,comm=", timeout: 10).out.split(separator: "\n") {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count == 3, let c = Double(parts[0]), let r = Int64(parts[1]) else { continue }
        rows.append((c, r * 1024, String(parts[2])))
    }
    let me = ProcessInfo.processInfo.processIdentifier
    return NSWorkspace.shared.runningApplications.compactMap { app -> AppUsage? in
        guard app.activationPolicy == .regular, app.processIdentifier != me, let b = app.bundleURL?.path else { return nil }
        let mine = rows.filter { $0.path.hasPrefix(b + "/") }
        return AppUsage(pid: app.processIdentifier, name: app.localizedName ?? (b as NSString).lastPathComponent,
                        bundleId: app.bundleIdentifier ?? "", icon: app.icon,
                        cpu: mine.reduce(0) { $0 + $1.cpu }, memory: mine.reduce(0) { $0 + $1.rss })
    }.sorted { $0.memory > $1.memory }
}

/// Asks an app to quit the normal way (same as ⌘Q). Never force-quits. Finder and Wasevo are left alone.
func quitApp(pid: pid_t) -> Bool {
    guard let app = NSRunningApplication(processIdentifier: pid),
          app.bundleIdentifier != "com.apple.finder", app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else { return false }
    log("QUIT (asked) \(app.localizedName ?? "") \(app.bundleIdentifier ?? "")")
    return app.terminate()
}

/// Live samples for the charts. Shared by the Monitor page and the menu bar.
final class SystemMonitor: ObservableObject {
    static let shared = SystemMonitor()
    struct Sample: Identifiable { let id = UUID(); let t: Date; let cpu: Double; let mem: Double }

    @Published var samples: [Sample] = []
    @Published var cpu: Double = 0
    @Published var memory = readMemory()
    @Published var battery = readBattery()
    @Published var thermal = ProcessInfo.processInfo.thermalState

    private var last = readCPUTicks()
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        tick()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        let now = readCPUTicks()
        cpu = cpuUsage(last, now)
        last = now
        memory = readMemory()
        thermal = ProcessInfo.processInfo.thermalState
        if samples.count % 15 == 0 { battery = readBattery() }
        samples.append(Sample(t: Date(), cpu: cpu, mem: memory.total > 0 ? Double(memory.used) / Double(memory.total) : 0))
        if samples.count > 90 { samples.removeFirst(samples.count - 90) }
    }
}
