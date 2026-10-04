import Foundation

/// Cada monitoramento que o usuário pode ligar ou desligar nos ajustes.
enum Module: String, CaseIterable, Identifiable {
    case cpu, memory, disk, network, battery, processes

    var id: String { rawValue }
    var key: String { "monitor.\(rawValue)" }
    var defaultOn: Bool { self != .processes }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultOn
    }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memória"
        case .disk: "Disco"
        case .network: "Rede"
        case .battery: "Bateria"
        case .processes: "Top 5 processos"
        }
    }

    var icon: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .network: "network"
        case .battery: "battery.75"
        case .processes: "list.number"
        }
    }

    var detail: String {
        switch self {
        case .cpu: "Uso total, por núcleo e número na barra de menu"
        case .memory: "Uso e pressão da memória"
        case .disk: "Espaço livre no disco"
        case .network: "Velocidade de download e upload"
        case .battery: "Nível, ciclos e capacidade máxima"
        case .processes: "Os que mais usam CPU e memória (leitura mais pesada)"
        }
    }
}
