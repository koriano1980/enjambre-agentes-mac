import Foundation

public struct EscenaVisual: Equatable, Sendable {
    public var cursores: [CursorVisual]
    public var aviso: String?

    public init(cursores: [CursorVisual], aviso: String? = nil) {
        self.cursores = cursores
        self.aviso = aviso
    }
}

/// Guion determinista para ver el enjambre sin Claude. Un ciclo dura 14 segundos.
public enum DemoGuion {
    public static let duracionCiclo: Double = 14

    public static func escena(tiempo: Double, agentes: [AgenteConfig]) -> EscenaVisual {
        let plantilla = agentes.isEmpty ? agentesPorDefecto() : agentes
        let t = tiempo.truncatingRemainder(dividingBy: duracionCiclo)
        let tiempoPositivo = t < 0 ? t + duracionCiclo : t
        if tiempoPositivo < 1.6 {
            return EscenaVisual(cursores: llegada(tiempo: tiempoPositivo, agentes: plantilla), aviso: "Modo demostración · sin modelos")
        }
        if tiempoPositivo < 7.4 {
            return EscenaVisual(cursores: trabajo(tiempo: tiempoPositivo, agentes: plantilla), aviso: "Modo demostración · sin modelos")
        }
        if tiempoPositivo < 12.2 {
            return EscenaVisual(cursores: enjambre(tiempo: tiempoPositivo, agentes: plantilla), aviso: "Enjambre")
        }
        return EscenaVisual(cursores: trabajo(tiempo: tiempoPositivo, agentes: plantilla), aviso: "Modo demostración · sin modelos")
    }

    /// Trozo de enjambre usado al terminar una orden con varios agentes.
    public static func celebracion(tiempo: Double, agentes: [AgenteConfig]) -> EscenaVisual {
        let plantilla = agentes.isEmpty ? agentesPorDefecto() : agentes
        return EscenaVisual(cursores: enjambre(tiempo: 8 + tiempo, agentes: plantilla), aviso: "Listo")
    }
}

private let burbujasDemo: [String: [String]] = [
    "programador": ["revisando el código", "ejecutando pruebas", "editando un archivo"],
    "investigador": ["buscando fuentes", "leyendo una página", "comparando datos"],
    "archivos": ["organizando carpetas", "mirando el Finder", "comprobando rutas"],
    "navegador": ["abriendo el navegador", "haciendo clic", "leyendo la página"],
    "escritor": ["redactando", "corrigiendo el tono", "guardando el texto"],
]

private func llegada(tiempo: Double, agentes: [AgenteConfig]) -> [CursorVisual] {
    agentes.enumerated().map { indice, agente in
        let progreso = suave(tiempo / 1.5)
        let origen = origenFuera(indice: indice, total: agentes.count)
        let x = origen.0 + (agente.anclaX - origen.0) * progreso
        let y = origen.1 + (agente.anclaY - origen.1) * progreso
        return CursorVisual(
            id: agente.id,
            nombre: agente.nombre,
            colorHex: agente.color,
            x: x,
            y: y,
            angulo: anguloDeMovimiento(dx: agente.anclaX - origen.0, dy: agente.anclaY - origen.1),
            burbuja: progreso > 0.72 ? "aquí" : nil,
            opacidad: 0.35 + 0.65 * progreso
        )
    }
}

private func trabajo(tiempo: Double, agentes: [AgenteConfig]) -> [CursorVisual] {
    agentes.enumerated().map { indice, agente in
        let fase = Double(indice) * 0.9
        let dx = 0.035 * sin(tiempo * 1.25 + fase)
        let dy = 0.028 * cos(tiempo * 1.05 + fase)
        let frases = burbujasDemo[agente.id] ?? ["trabajando"]
        let cual = Int(tiempo / 1.5) % frases.count
        return CursorVisual(
            id: agente.id,
            nombre: agente.nombre,
            colorHex: agente.color,
            x: min(0.96, max(0.04, agente.anclaX + dx)),
            y: min(0.94, max(0.06, agente.anclaY + dy)),
            angulo: anguloDeMovimiento(dx: cos(tiempo * 1.25 + fase), dy: -sin(tiempo * 1.05 + fase), minimo: 0),
            burbuja: frases[cual],
            opacidad: agente.requiereRed ? 1 : 1,
            etiqueta: etiquetaDemo(agente),
            dormido: false
        )
    }
}

private func enjambre(tiempo: Double, agentes: [AgenteConfig]) -> [CursorVisual] {
    let total = 26
    return (0..<total).map { indice in
        let agente = agentes[indice % agentes.count]
        let fase = Double(indice) * 0.55
        let x = 0.5 + 0.46 * sin(tiempo * 0.85 + fase)
        let y = 0.50 + 0.40 * cos(tiempo * 0.67 + fase * 1.17)
        let dx = 0.46 * 0.85 * cos(tiempo * 0.85 + fase)
        let dy = -0.40 * 0.67 * sin(tiempo * 0.67 + fase * 1.17)
        let principal = indice < agentes.count
        return CursorVisual(
            id: principal ? agente.id : "fantasma-\(indice)",
            nombre: agente.nombre,
            colorHex: agente.color,
            x: min(0.98, max(0.02, x)),
            y: min(0.96, max(0.04, y)),
            angulo: atan2(dx, -dy),
            burbuja: principal && indice == 0 ? "enjambre" : nil,
            opacidad: principal ? 1 : 0.92,
            fantasma: !principal
        )
    }
}

public extension DemoGuion {
    static let guionConversacion: [(tiempo: Double, autor: String, texto: String)] = [
        (1.8, "Coordinador", "Propongo partir la orden: código, archivos y una segunda opinión."),
        (3.4, "Programador", "Puedo dejar el cambio pequeño y cubrirlo con una prueba."),
        (4.8, "Escritor", "El resumen debería ir en español y caber en un párrafo."),
        (6.2, "ChatGPT", "Sugiero mirar el borde de la ventana antes de dar el texto por bueno."),
        (7.0, "Coordinador", "Fusión: Programador implementa y Escritor resume. ¿Apruebas?"),
    ]

    static func mensajes(hasta tiempo: Double) -> [(autor: String, texto: String)] {
        let t = tiempo.truncatingRemainder(dividingBy: duracionCiclo)
        let positivo = t < 0 ? t + duracionCiclo : t
        return guionConversacion.filter { $0.tiempo <= positivo }.map { ($0.autor, $0.texto) }
    }
}

private func etiquetaDemo(_ agente: AgenteConfig) -> String {
    switch agente.modalidad {
    case .local: return "local"
    case .online: return "en línea"
    case .gui: return "app"
    }
}

private func origenFuera(indice: Int, total: Int) -> (Double, Double) {
    let lado = indice % 4
    let fraccion = total <= 1 ? 0.5 : Double(indice) / Double(total - 1)
    switch lado {
    case 0: return (-0.12, 0.15 + 0.7 * fraccion)
    case 1: return (1.12, 0.15 + 0.7 * fraccion)
    case 2: return (0.15 + 0.7 * fraccion, -0.12)
    default: return (0.15 + 0.7 * fraccion, 1.12)
    }
}
