import Foundation

public struct ModeloAsignado: Equatable, Sendable {
    public var nombre: String
    public var proveedor: ProveedorModelo
    public var memoriaGB: Double
    public var vision: Bool
}

public struct PresetHardware: Equatable, Sendable {
    public var id: String
    public var titulo: String
    public var presupuestoGB: Double
    public var modelos: [String: ModeloAsignado]
}

public enum MemoriaEquipo {
    public static func gigabytes() -> Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }
}

public enum PresetsHardware {
    public static let pro24 = PresetHardware(
        id: "pro-24",
        titulo: "MacBook Pro 24 GB",
        presupuestoGB: 17,
        modelos: [
            "coordinador": ModeloAsignado(nombre: "qwen2.5-coder:14b", proveedor: .ollama, memoriaGB: 9.0, vision: false),
            "programador": ModeloAsignado(nombre: "qwen2.5-coder:14b", proveedor: .ollama, memoriaGB: 9.0, vision: false),
            "escritor": ModeloAsignado(nombre: "qwen2.5:7b", proveedor: .ollama, memoriaGB: 4.7, vision: false),
            "archivos": ModeloAsignado(nombre: "qwen2.5:7b", proveedor: .ollama, memoriaGB: 4.7, vision: false),
            "ojos": ModeloAsignado(nombre: "qwen2.5vl:3b", proveedor: .ollama, memoriaGB: 3.2, vision: true),
        ]
    )

    public static let mini16 = PresetHardware(
        id: "mini-16",
        titulo: "Mac mini 16 GB",
        presupuestoGB: 11,
        modelos: [
            "coordinador": ModeloAsignado(nombre: "qwen2.5-coder:7b", proveedor: .ollama, memoriaGB: 4.7, vision: false),
            "programador": ModeloAsignado(nombre: "qwen2.5-coder:7b", proveedor: .ollama, memoriaGB: 4.7, vision: false),
            "escritor": ModeloAsignado(nombre: "llama3.2:3b", proveedor: .ollama, memoriaGB: 2.0, vision: false),
            "archivos": ModeloAsignado(nombre: "qwen2.5:1.5b", proveedor: .ollama, memoriaGB: 1.1, vision: false),
            "ojos": ModeloAsignado(nombre: "moondream", proveedor: .ollama, memoriaGB: 1.8, vision: true),
        ]
    )

    public static func elegir(gigabytes: Double, forzado: String) -> PresetHardware {
        switch forzado.lowercased() {
        case "pro-24", "pro24", "24": return pro24
        case "mini-16", "mini16", "16": return mini16
        default: return gigabytes >= 20 ? pro24 : mini16
        }
    }

    /// Suma de modelos distintos. Los agentes que comparten modelo no duplican la RAM.
    public static func memoriaResidente(_ preset: PresetHardware) -> Double {
        var vistos = Set<String>()
        var total = 0.0
        for modelo in preset.modelos.values where vistos.insert(modelo.nombre).inserted {
            total += modelo.memoriaGB
        }
        return total
    }
}

/// Una sola instancia por modelo y un tope de RAM. Los agentes que comparten modelo hacen cola.
public actor ColaModelos {
    public let presupuestoGB: Double
    private var memoria: [String: Double] = [:]
    private var ocupado: Set<String> = []
    private var espera: [CheckedContinuation<Void, Never>] = []

    public init(presupuestoGB: Double) {
        self.presupuestoGB = max(1, presupuestoGB)
    }

    public func adquirir(clave: String, memoriaGB: Double) async {
        let peso = max(0.1, memoriaGB)
        while !puede(clave: clave, peso: peso) {
            await withCheckedContinuation { espera.append($0) }
        }
        memoria[clave] = peso
        ocupado.insert(clave)
    }

    public func liberar(clave: String) {
        ocupado.remove(clave)
        if !ocupado.contains(clave) {
            memoria[clave] = nil
        }
        let pendientes = espera
        espera.removeAll()
        for continuacion in pendientes {
            continuacion.resume()
        }
    }

    public func residentesGB() -> Double {
        memoria.values.reduce(0, +)
    }

    private func puede(clave: String, peso: Double) -> Bool {
        if ocupado.contains(clave) { return false }
        let otros = memoria.filter { $0.key != clave }.values.reduce(0, +)
        return otros + peso <= presupuestoGB + 0.05
    }
}
