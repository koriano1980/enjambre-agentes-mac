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
            opacidad: 1,
            etiqueta: "",
            dormido: false,
            escala: 0.7
        )
    }
}

/// Enjambre como en el estudio: muchas flechas pequeñas, repartidas, no cinco cursores grandes.
/// El movimiento está medido sobre el reel: aparecen en ráfaga, se quedan dispersas y solo tiemblan un poco.
private func enjambre(tiempo: Double, agentes: [AgenteConfig]) -> [CursorVisual] {
    let total = 48
    let base = max(agentes.count, 1)
    return (0..<total).map { indice in
        let agente = agentes[indice % base]
        let columna = indice % 8
        let fila = indice / 8
        let fase = Double(indice) * 0.73
        let destinoX = 0.07 + Double(columna) * 0.112 + 0.012 * sin(tiempo * 1.55 + fase)
        let destinoY = 0.10 + Double(fila) * 0.135 + 0.010 * cos(tiempo * 1.25 + fase * 1.15)
        let retraso = 7.4 + Double(indice) * 0.028
        let llegada = suave(min(1, max(0, (tiempo - retraso) / 0.65)))
        let origen = origenFuera(indice: indice, total: total)
        let principal = indice < agentes.count
        return CursorVisual(
            id: principal ? agente.id : "fantasma-\(indice)",
            nombre: agente.nombre,
            colorHex: principal ? agente.color : "#F4F6F8",
            x: origen.0 + (destinoX - origen.0) * llegada,
            y: origen.1 + (destinoY - origen.1) * llegada,
            angulo: -1.05 + Double(indice % 8) * 0.38 + 0.06 * sin(tiempo * 0.8 + fase),
            burbuja: nil,
            opacidad: 0.55 + 0.45 * llegada,
            fantasma: !principal,
            etiqueta: "",
            escala: principal ? 0.62 : 0.48
        )
    }
}

public struct BloqueLinea: Equatable, Sendable {
    public var agenteID: String
    public var titulo: String
    public var inicio: Double
    public var duracion: Double
    public var progreso: Double

    public init(agenteID: String, titulo: String, inicio: Double, duracion: Double, progreso: Double) {
        self.agenteID = agenteID
        self.titulo = titulo
        self.inicio = inicio
        self.duracion = duracion
        self.progreso = progreso
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

    static func lineaDeTiempo(tiempo: Double, agentes: [AgenteConfig]) -> [BloqueLinea] {
        let plantilla = agentes.isEmpty ? agentesPorDefecto() : agentes
        let t = tiempo.truncatingRemainder(dividingBy: duracionCiclo)
        let ahora = t < 0 ? t + duracionCiclo : t
        let titulos = ["revisar", "editar", "comprobar", "redactar", "mirar"]
        return plantilla.enumerated().map { indice, agente in
            let inicio = 0.6 + Double(indice) * 0.35
            let duracion = 6.5
            let progreso = min(1, max(0, (ahora - inicio) / duracion))
            return BloqueLinea(
                agenteID: agente.id,
                titulo: titulos[indice % titulos.count],
                inicio: inicio / duracionCiclo,
                duracion: duracion / duracionCiclo,
                progreso: progreso
            )
        }
    }

    static func trazaJSON(segundos: Double, fps: Double, agentes: [AgenteConfig]) -> String {
        var lineas: [String] = []
        let paso = 1.0 / max(1, fps)
        var t = 0.0
        while t <= segundos + 0.0001 {
            let escena = escena(tiempo: t, agentes: agentes)
            let cursores = escena.cursores.map { cursor -> ValorJSON in
                .objeto([
                    "id": .texto(cursor.id),
                    "n": .texto(cursor.nombre),
                    "c": .texto(cursor.colorHex),
                    "x": .numero(cursor.x),
                    "y": .numero(cursor.y),
                    "a": .numero(cursor.angulo),
                    "f": .bool(cursor.fantasma),
                    "e": .numero(cursor.escala),
                    "o": .numero(cursor.opacidad),
                ])
            }
            let bloques = lineaDeTiempo(tiempo: t, agentes: agentes).map { bloque -> ValorJSON in
                .objeto([
                    "id": .texto(bloque.agenteID),
                    "t": .texto(bloque.titulo),
                    "i": .numero(bloque.inicio),
                    "d": .numero(bloque.duracion),
                    "p": .numero(bloque.progreso),
                ])
            }
            lineas.append(ValorJSON.objeto([
                "t": .numero(t),
                "aviso": .texto(escena.aviso ?? ""),
                "cursores": .lista(cursores),
                "bloques": .lista(bloques),
            ]).textoPlano)
            t += paso
        }
        return lineas.joined(separator: "\n")
    }

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
