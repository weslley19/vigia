import SwiftUI

@main
struct VigiaApp: App {
    private let monitor = SystemMonitor()
    @AppStorage(Module.cpu.key) private var showCPU = Module.cpu.defaultOn

    init() {
        monitor.start()
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(monitor: monitor)
        } label: {
            Image(systemName: "gauge.with.dots.needle.50percent")
            if showCPU {
                Text("\(Int((monitor.cpu * 100).rounded()))%")
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
