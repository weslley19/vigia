import Foundation
import Observation

@Observable
final class SystemMonitor {
    static let interval: TimeInterval = 5

    // CPU
    private(set) var cpu = 0.0              // 0...1
    private(set) var cores: [Double] = []

    // Memória / disco
    private(set) var memory = MemoryReading(used: 0, total: ProcessInfo.processInfo.physicalMemory, pressure: .normal)
    private(set) var diskFree: Int64 = 0
    private(set) var diskTotal: Int64 = 0

    // Rede (bytes/s)
    private(set) var download = 0.0
    private(set) var upload = 0.0

    private(set) var battery: BatteryReading?
    private(set) var topCPU: [ProcessUsage] = []
    private(set) var topMemory: [ProcessUsage] = []

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var systemCapacity: Int?
    @ObservationIgnored private var lastCapacityCheck = Date.distantPast
    @ObservationIgnored private var lastTicks: [[UInt32]] = []
    @ObservationIgnored private var lastNet: (rx: UInt32, tx: UInt32)?
    @ObservationIgnored private var lastProcCPU: [pid_t: UInt64] = [:]
    @ObservationIgnored private var lastSample = Date()

    func start() {
        guard timer == nil else { return }
        sample()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Chamado quando o usuário liga/desliga um monitoramento: atualiza já e de novo logo depois,
    /// para os que dependem de diferença entre duas leituras (CPU, rede, processos) mostrarem valor.
    func refresh() {
        sample()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    private func sample() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSample)
        lastSample = now

        // Só lê o que está ligado; o que está desligado perde a base de comparação,
        // para não calcular uma taxa enorme quando for religado.
        if Module.cpu.isEnabled {
            sampleCPU()
        } else {
            lastTicks = []; cpu = 0; cores = []
        }

        if Module.memory.isEnabled { memory = Samplers.memory() }
        if Module.disk.isEnabled { (diskFree, diskTotal) = Samplers.disk() }

        if Module.battery.isEnabled {
            battery = Samplers.battery()
            refreshSystemCapacity()
            if let systemCapacity { battery?.maxCapacity = systemCapacity }
        } else {
            battery = nil
        }

        if Module.network.isEnabled, elapsed > 0 {
            sampleNetwork(elapsed: elapsed)
        } else if !Module.network.isEnabled {
            lastNet = nil; download = 0; upload = 0
        }

        if Module.processes.isEnabled, elapsed > 0 {
            sampleProcesses(elapsed: elapsed)
        } else if !Module.processes.isEnabled {
            lastProcCPU = [:]; topCPU = []; topMemory = []
        }
    }

    /// A capacidade máxima muda devagar: consulta o sistema em segundo plano uma vez por dia.
    private func refreshSystemCapacity() {
        guard Date().timeIntervalSince(lastCapacityCheck) > 24 * 60 * 60 else { return }
        lastCapacityCheck = Date()
        Task.detached {
            let value = Samplers.systemMaxCapacity()
            await MainActor.run { [weak self] in
                if let value { self?.systemCapacity = value }
            }
        }
    }

    private func sampleCPU() {
        let ticks = Samplers.cpuTicks()
        defer { lastTicks = ticks }
        guard ticks.count == lastTicks.count else { return }

        var busyTotal = 0.0, allTotal = 0.0
        cores = zip(ticks, lastTicks).map { now, before in
            let delta = zip(now, before).map { Double($0 &- $1) }   // user, system, idle, nice
            let all = delta.reduce(0, +)
            let busy = all - delta[2]
            busyTotal += busy
            allTotal += all
            return all > 0 ? busy / all : 0
        }
        cpu = allTotal > 0 ? busyTotal / allTotal : 0
    }

    private func sampleNetwork(elapsed: TimeInterval) {
        let net = Samplers.networkBytes()
        defer { lastNet = net }
        guard let last = lastNet else { return }
        download = Double(net.rx &- last.rx) / elapsed
        upload = Double(net.tx &- last.tx) / elapsed
    }

    private func sampleProcesses(elapsed: TimeInterval) {
        let processes = Samplers.processes()
        var grouped: [String: ProcessUsage] = [:]
        var current: [pid_t: UInt64] = [:]

        for process in processes {
            current[process.pid] = process.cpuNs
            // Processo novo ainda não tem base de comparação.
            let delta = lastProcCPU[process.pid].map { process.cpuNs &- $0 } ?? 0
            let percent = Double(delta) / (elapsed * 1_000_000_000) * 100
            var usage = grouped[process.name] ?? ProcessUsage(name: process.name, cpu: 0, memory: 0)
            usage.cpu += percent
            usage.memory += process.memory
            grouped[process.name] = usage
        }
        lastProcCPU = current

        let all = Array(grouped.values)
        topCPU = Array(all.sorted { $0.cpu > $1.cpu }.prefix(5))
        topMemory = Array(all.sorted { $0.memory > $1.memory }.prefix(5))
    }
}
