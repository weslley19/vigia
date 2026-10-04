import Foundation
import Darwin
import IOKit
import IOKit.ps

// Leituras de baixo nível do sistema. Cada função devolve um valor pontual;
// o cálculo de taxas (CPU, rede) fica no SystemMonitor.

struct MemoryReading {
    var used: UInt64
    var total: UInt64
    var pressure: Pressure

    enum Pressure { case normal, warning, critical }
}

struct BatteryReading {
    var level: Int
    var isCharging: Bool
    var onACPower: Bool
    var cycles: Int?
    var maxCapacity: Int?   // saúde da bateria, % da capacidade de fábrica
}

struct ProcessUsage: Identifiable {
    var id: String { name }
    let name: String
    var cpu: Double      // % de um núcleo (pode passar de 100)
    var memory: UInt64   // bytes residentes
}

enum Samplers {
    // MARK: CPU

    /// Ticks acumulados por núcleo: [user, system, idle, nice].
    static func cpuTicks() -> [[UInt32]] {
        var numCPU: natural_t = 0
        var info: processor_info_array_t?
        var count: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPU, &info, &count) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let states = Int(CPU_STATE_MAX)
        return (0..<Int(numCPU)).map { core in
            let base = core * states
            return [CPU_STATE_USER, CPU_STATE_SYSTEM, CPU_STATE_IDLE, CPU_STATE_NICE].map {
                UInt32(bitPattern: info[base + Int($0)])
            }
        }
    }

    // MARK: Memória

    static func memory() -> MemoryReading {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        // Mesma conta do Monitor de Atividade: app + fixa + comprimida.
        let pages = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
            &+ UInt64(stats.wire_count) &+ UInt64(stats.compressor_page_count)
        let used = result == KERN_SUCCESS ? pages * UInt64(pageSize) : 0

        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        let pressure: MemoryReading.Pressure = level >= 4 ? .critical : level >= 2 ? .warning : .normal

        return MemoryReading(used: used, total: ProcessInfo.processInfo.physicalMemory, pressure: pressure)
    }

    // MARK: Disco

    static func disk() -> (free: Int64, total: Int64) {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return (0, 0) }
        return (values.volumeAvailableCapacityForImportantUsage ?? 0, Int64(values.volumeTotalCapacity ?? 0))
    }

    // MARK: Rede

    /// Bytes totais (recebidos, enviados) das interfaces `en*`. Os contadores são de 32 bits
    /// e dão a volta; por isso a soma é feita com wrap e a diferença também.
    static func networkBytes() -> (rx: UInt32, tx: UInt32) {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return (0, 0) }
        defer { freeifaddrs(list) }

        var rx: UInt32 = 0, tx: UInt32 = 0
        var cursor = list
        while let entry = cursor {
            let ifa = entry.pointee
            if let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
               let data = ifa.ifa_data, String(cString: ifa.ifa_name).hasPrefix("en") {
                let stats = data.assumingMemoryBound(to: if_data.self).pointee
                rx = rx &+ stats.ifi_ibytes
                tx = tx &+ stats.ifi_obytes
            }
            cursor = ifa.ifa_next
        }
        return (rx, tx)
    }

    // MARK: Bateria

    static func battery() -> BatteryReading? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  let level = info[kIOPSCurrentCapacityKey] as? Int else { continue }
            return BatteryReading(
                level: level,
                isCharging: info[kIOPSIsChargingKey] as? Bool ?? false,
                onACPower: info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                cycles: registryInt("CycleCount"),
                maxCapacity: maxCapacityPercent()
            )
        }
        return nil
    }

    /// Capacidade máxima como o macOS informa (o mesmo número dos Ajustes do Sistema).
    /// Não há uma conta pública que reproduza esse valor com exatidão, então perguntamos ao sistema.
    nonisolated static func systemMaxCapacity() -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPPowerDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["SPPowerDataType"] as? [[String: Any]] else { return nil }
        for item in items {
            if let health = item["sppower_battery_health_info"] as? [String: Any],
               let text = health["sppower_battery_health_maximum_capacity"] as? String {
                return Int(text.filter(\.isNumber))
            }
        }
        return nil
    }

    /// Reserva: capacidade atual de carga / capacidade de fábrica (costuma ficar uns pontos abaixo).
    private static func maxCapacityPercent() -> Int? {
        guard let nominal = registryInt("NominalChargeCapacity"),
              let design = registryInt("DesignCapacity"), design > 0 else { return nil }
        return Int((Double(nominal) / Double(design) * 100).rounded())
    }

    private static func registryInt(_ key: String) -> Int? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        return value?.takeRetainedValue() as? Int
    }

    // MARK: Processos

    /// Tempo de CPU acumulado (ns) e memória residente de cada processo visível, agrupados por nome.
    static func processes() -> [(pid: pid_t, name: String, cpuNs: UInt64, memory: UInt64)] {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(bytes) / MemoryLayout<pid_t>.size + 32)
        let filled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        let count = Int(filled) / MemoryLayout<pid_t>.size

        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)

        var result: [(pid_t, String, UInt64, UInt64)] = []
        for pid in pids.prefix(count) where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            let ticks = info.pti_total_user &+ info.pti_total_system
            let ns = ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
            result.append((pid, processName(pid), ns, info.pti_resident_size))
        }
        return result
    }

    private static func processName(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return "?" }
        let parts = String(cString: buffer).split(separator: "/")
        if let app = parts.last(where: { $0.hasSuffix(".app") }) { return String(app.dropLast(4)) }
        return String(parts.last ?? "?")
    }
}
