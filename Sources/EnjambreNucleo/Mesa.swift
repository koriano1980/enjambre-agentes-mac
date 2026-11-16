import Foundation

public enum RutaAgente: Equatable, Sendable {
    case local(ProveedorModelo, String, Double)
    case remoto(String, String)
    case nube(ProveedorModelo, String)
    case gui(String)
    case dormido(String)
}

public enum AporteUsuario: Equatable, Sendable {
    case mensaje
    case aprobar
    case vetar
}

public enum MesaDebate {
    public static func ruta(de agente: AgenteConfig, enLinea: Bool, nodosVivos: Set<String>) -> RutaAgente {
        if !agente.nodo.isEmpty {
            if nodosVivos.contains(agente.nodo) {
                return .remoto(agente.nodo, agente.modelo)
            }
            return .dormido("el nodo \(agente.nodo) no responde")
        }
        if agente.proveedor == .gui || agente.modalidad == .gui {
            if agente.requiereRed && !enLinea { return .dormido("sin internet") }
            return .gui(agente.id)
        }
        if agente.modalidad == .online || agente.requiereRed {
            if !enLinea { return .dormido("sin internet") }
            return .nube(agente.proveedor, agente.modelo)
        }
        return .local(agente.proveedor, agente.modelo, agente.memoriaGB > 0 ? agente.memoriaGB : 2)
    }

    public static func activos(_ agentes: [AgenteConfig], enLinea: Bool, nodosVivos: Set<String>) -> [AgenteConfig] {
        agentes.filter {
            if case .dormido = ruta(de: $0, enLinea: enLinea, nodosVivos: nodosVivos) { return false }
            return true
        }
    }

    public static func participantes(agentes: [AgenteConfig], enLinea: Bool, incluirGUI: Bool, maximo: Int, nodosVivos: Set<String> = []) -> [AgenteConfig] {
        let utiles = activos(agentes, enLinea: enLinea, nodosVivos: nodosVivos).filter { agente in
            guard agente.debate, !agente.coordinador else { return false }
            if agente.modalidad == .gui || agente.proveedor == .gui { return incluirGUI }
            return true
        }
        return Array(utiles.prefix(max(1, maximo)))
    }

    public static func reasignar(_ tarea: TareaPlan, activos: [AgenteConfig]) -> TareaPlan {
        if activos.contains(where: { $0.id == tarea.agente }) { return tarea }
        let origen = activos.first { $0.id == tarea.agente }
        let destino = activos.max { solape($0, con: origen) < solape($1, con: origen) }
            ?? activos.first { $0.coordinador }
            ?? activos.first
        guard let destino else { return tarea }
        var copia = tarea
        copia.agente = destino.id
        return copia
    }

    public static func planRequiereAprobacion(plan: Plan, politica: PoliticaAprobacion, sugerenciasExternas: Bool) -> Bool {
        switch politica {
        case .nunca: return false
        case .siempre: return true
        case .siDestructivo:
            if sugerenciasExternas { return true }
            let texto = plan.tareas.map(\.objetivo).joined(separator: "\n").lowercased()
            let marcas = ["rm ", "borrar", "eliminar", "enviar", "comprar", "purchase", "git push", "sudo", "format"]
            return marcas.contains { texto.contains($0) }
        }
    }

    public static func interpretarAporte(_ texto: String, decisionPendiente: Bool) -> AporteUsuario {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard decisionPendiente else { return .mensaje }
        if respuestaAfirmativa(limpio) || limpio == "aprobar" || limpio == "aprobado" { return .aprobar }
        if ["no", "veto", "vetar", "cancela", "cancelar", "parar", "detente"].contains(limpio) { return .vetar }
        return .mensaje
    }

    public static func menciones(en texto: String, agentes: [AgenteConfig]) -> [String] {
        var encontradas: [String] = []
        for agente in agentes {
            let marcas = ["@\(agente.id)", "@\(agente.nombre)"]
            if marcas.contains(where: { texto.localizedCaseInsensitiveContains($0) }) {
                encontradas.append(agente.id)
            }
        }
        return encontradas
    }

    private static func solape(_ agente: AgenteConfig, con otro: AgenteConfig?) -> Int {
        guard let otro else { return agente.coordinador ? 0 : 1 }
        return Set(agente.herramientas).intersection(otro.herramientas).count
    }
}

public enum OrigenMensaje: String, Codable, Equatable, Sendable {
    case usuario
    case agente
    case externo
    case sistema
    case telegram
    case webhook
}

public enum DecisionSala: Equatable, Sendable {
    case aprobar
    case vetar
    case silencio
}

public struct MensajeSala: Equatable, Sendable, Identifiable, Codable {
    public var id: Int
    public var autor: String
    public var origen: OrigenMensaje
    public var texto: String
    public var sugerencia: Bool
    public var menciones: [String]

    public init(id: Int, autor: String, origen: OrigenMensaje, texto: String, sugerencia: Bool, menciones: [String]) {
        self.id = id
        self.autor = autor
        self.origen = origen
        self.texto = texto
        self.sugerencia = sugerencia
        self.menciones = menciones
    }
}

public actor Sala {
    private var mensajes: [MensajeSala] = []
    private var siguiente = 1
    private var espera: CheckedContinuation<DecisionSala, Never>?
    private var generacion = 0
    private var decisionPendiente = false
    public var alPublicar: (@Sendable (MensajeSala) -> Void)?

    public init() {}

    public func publicar(autor: String, origen: OrigenMensaje, texto: String, menciones: [String] = []) -> MensajeSala {
        let mensaje = MensajeSala(
            id: siguiente,
            autor: autor,
            origen: origen,
            texto: texto,
            sugerencia: origen == .externo || origen == .telegram || origen == .webhook,
            menciones: menciones
        )
        siguiente += 1
        mensajes.append(mensaje)
        if mensajes.count > 400 { mensajes.removeFirst(mensajes.count - 400) }
        alPublicar?(mensaje)
        return mensaje
    }

    public func recientes(_ n: Int = 80) -> [MensajeSala] {
        Array(mensajes.suffix(n))
    }

    public func sugerencias(desde id: Int) -> [MensajeSala] {
        mensajes.filter { $0.id > id && $0.sugerencia }
    }

    public func marcarDecisionPendiente(_ valor: Bool) {
        decisionPendiente = valor
    }

    public func hayDecisionPendiente() -> Bool { decisionPendiente }

    public func resolver(_ decision: DecisionSala) {
        decisionPendiente = false
        generacion += 1
        espera?.resume(returning: decision)
        espera = nil
    }

    public func esperarDecision(segundos: Double) async -> DecisionSala {
        decisionPendiente = true
        generacion += 1
        let generacionActual = generacion
        return await withCheckedContinuation { (cont: CheckedContinuation<DecisionSala, Never>) in
            self.espera = cont
            Task { await self.vencer(segundos: segundos, generacion: generacionActual) }
        }
    }

    private func vencer(segundos: Double, generacion esperada: Int) async {
        let nanos = UInt64(max(1, segundos) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanos)
        guard generacion == esperada, let espera else { return }
        self.espera = nil
        decisionPendiente = false
        espera.resume(returning: .silencio)
    }
}
