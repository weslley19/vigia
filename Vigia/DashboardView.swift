import SwiftUI
import AppKit

struct DashboardView: View {
    let monitor: SystemMonitor
    @State private var processSort = ProcessSort.cpu
    @State private var showingSettings = false

    @AppStorage(Module.cpu.key) private var showCPU = Module.cpu.defaultOn
    @AppStorage(Module.memory.key) private var showMemory = Module.memory.defaultOn
    @AppStorage(Module.disk.key) private var showDisk = Module.disk.defaultOn
    @AppStorage(Module.network.key) private var showNetwork = Module.network.defaultOn
    @AppStorage(Module.battery.key) private var showBattery = Module.battery.defaultOn
    @AppStorage(Module.processes.key) private var showProcesses = Module.processes.defaultOn

    enum ProcessSort: String, CaseIterable {
        case cpu = "CPU", memory = "Memória"
    }

    private var anyEnabled: Bool {
        showCPU || showMemory || showDisk || showNetwork || showBattery || showProcesses
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            if showingSettings {
                SettingsView(monitor: monitor)
            } else {
                monitors
            }
            footer
        }
        .padding(14)
        .frame(width: 360)
    }

    @ViewBuilder
    private var monitors: some View {
        if !anyEnabled {
            ContentUnavailableView("Nenhum monitoramento ativo",
                                   systemImage: "switch.2",
                                   description: Text("Ligue algum nos ajustes (engrenagem)."))
        }
        if showCPU { cpuCard }
        if showMemory { memoryCard }
        if showDisk || showNetwork {
            HStack(spacing: 10) {
                if showDisk { diskCard }
                if showNetwork { networkCard }
            }
        }
        if showBattery, let battery = monitor.battery { batteryCard(battery) }
        if showProcesses { processesCard }
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack {
            Label(showingSettings ? "Ajustes" : "Vigia",
                  systemImage: showingSettings ? "gearshape" : "gauge.with.dots.needle.50percent")
                .font(.headline)
            Spacer()
            if !showingSettings {
                Text("atualiza a cada \(Int(SystemMonitor.interval))s")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Button {
                showingSettings.toggle()
            } label: {
                Image(systemName: showingSettings ? "checkmark.circle.fill" : "gearshape")
                    .font(.system(size: 14))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(showingSettings ? Color.accentColor : .secondary)
            .help(showingSettings ? "Voltar" : "Ajustes")
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Sair", systemImage: "power")
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Cards

    private var cpuCard: some View {
        Card(title: "CPU", icon: "cpu", value: percent(monitor.cpu)) {
            UsageBar(value: monitor.cpu)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(monitor.cores.enumerated()), id: \.offset) { _, core in
                    UsageColumn(value: core)
                }
            }
            .frame(height: 28)
        }
    }

    private var memoryCard: some View {
        let memory = monitor.memory
        let fraction = memory.total > 0 ? Double(memory.used) / Double(memory.total) : 0
        return Card(title: "Memória", icon: "memorychip", value: percent(fraction)) {
            UsageBar(value: fraction)
            HStack {
                Text("\(bytes(Int64(memory.used))) de \(bytes(Int64(memory.total)))")
                Spacer()
                Circle().fill(pressureColor(memory.pressure)).frame(width: 7, height: 7)
                Text(pressureLabel(memory.pressure))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var diskCard: some View {
        let used = monitor.diskTotal - monitor.diskFree
        let fraction = monitor.diskTotal > 0 ? Double(used) / Double(monitor.diskTotal) : 0
        return Card(title: "Disco", icon: "internaldrive", value: bytes(monitor.diskFree)) {
            UsageBar(value: fraction)
            Text("livres de \(bytes(monitor.diskTotal))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var networkCard: some View {
        Card(title: "Rede", icon: "network", value: nil) {
            VStack(alignment: .leading, spacing: 4) {
                rateRow("arrow.down", monitor.download, .blue)
                rateRow("arrow.up", monitor.upload, .orange)
            }
        }
    }

    private func rateRow(_ icon: String, _ rate: Double, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(color).font(.caption.weight(.bold))
            Text("\(bytes(Int64(rate)))/s").font(.callout.monospacedDigit())
        }
    }

    private func batteryCard(_ battery: BatteryReading) -> some View {
        let state = battery.isCharging ? "carregando" : battery.onACPower ? "na tomada" : "na bateria"
        return Card(title: "Bateria", icon: battery.isCharging ? "battery.100.bolt" : "battery.75",
                    value: "\(battery.level)%") {
            UsageBar(value: Double(battery.level) / 100, inverted: true)
            HStack {
                Text(state)
                Spacer()
                if let cycles = battery.cycles { Text("\(cycles) ciclos") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let max = battery.maxCapacity {
                HStack {
                    Text("Capacidade máxima")
                    Spacer()
                    Text("\(max)%").fontWeight(.semibold).monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var processesCard: some View {
        let list = processSort == .cpu ? monitor.topCPU : monitor.topMemory
        return Card(title: "Top 5 processos", icon: "list.number", value: nil) {
            Picker("", selection: $processSort) {
                ForEach(ProcessSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(spacing: 5) {
                ForEach(list) { process in
                    HStack {
                        Text(process.name).lineLimit(1)
                        Spacer()
                        Text(processSort == .cpu ? String(format: "%.1f%%", process.cpu)
                                                 : bytes(Int64(process.memory)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }

    // MARK: - Formatação

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .memory)
    }

    private func pressureColor(_ pressure: MemoryReading.Pressure) -> Color {
        switch pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    private func pressureLabel(_ pressure: MemoryReading.Pressure) -> String {
        switch pressure {
        case .normal: "pressão normal"
        case .warning: "pressão alta"
        case .critical: "pressão crítica"
        }
    }
}

// MARK: - Componentes

private struct Card<Content: View>: View {
    let title: String
    let icon: String
    let value: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let value {
                    Text(value).font(.callout.weight(.semibold).monospacedDigit())
                }
            }
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

private func usageColor(_ value: Double, inverted: Bool = false) -> Color {
    let load = inverted ? 1 - value : value
    return load < 0.6 ? .green : load < 0.85 ? .orange : .red
}

private struct UsageBar: View {
    let value: Double
    var inverted = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(usageColor(value, inverted: inverted))
                    .frame(width: max(4, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

private struct UsageColumn: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            VStack {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 2)
                    .fill(usageColor(value))
                    .frame(height: max(2, geo.size.height * min(max(value, 0), 1)))
            }
        }
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 2))
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

// MARK: - Ajustes

private struct SettingsView: View {
    let monitor: SystemMonitor

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Module.allCases) { module in
                ModuleToggleRow(module: module, onChange: monitor.refresh)
            }
            Text("Monitoramentos desligados não são lidos, então não gastam recurso.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
    }
}

private struct ModuleToggleRow: View {
    let module: Module
    let onChange: () -> Void
    @AppStorage private var isOn: Bool

    init(module: Module, onChange: @escaping () -> Void) {
        self.module = module
        self.onChange = onChange
        _isOn = AppStorage(wrappedValue: module.defaultOn, module.key)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: module.icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(module.title).font(.callout.weight(.medium))
                Text(module.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        .onChange(of: isOn) { onChange() }
    }
}
