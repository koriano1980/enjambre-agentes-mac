import Foundation

/// Descripción de una app o web de chat. Se edita en YAML; no hace falta recompilar para añadir otra.
public struct AdaptadorChat: Equatable, Sendable {
    public var id: String
    public var nombre: String
    public var tipo: String
    public var aplicacion: String
    public var url: String
    public var navegador: String
    public var rolEntrada: String
    public var pistaEntrada: String
    public var teclaEnviar: String
    public var rolRespuesta: String
    public var esperaSegundos: Double
    public var participaEnDebate: Bool
    public var mostrarCursor: Bool
    public var requiereRed: Bool
    public var color: String
    public var anclaX: Double
    public var anclaY: Double

    public init(id: String, nombre: String, tipo: String, aplicacion: String, url: String = "", navegador: String = "Safari", rolEntrada: String = "AXTextArea", pistaEntrada: String = "", teclaEnviar: String = "return", rolRespuesta: String = "AXStaticText", esperaSegundos: Double = 40, participaEnDebate: Bool = true, mostrarCursor: Bool = true, requiereRed: Bool = true, color: String = "#8E8E93", anclaX: Double = 0.5, anclaY: Double = 0.4) {
        self.id = id
        self.nombre = nombre
        self.tipo = tipo
        self.aplicacion = aplicacion
        self.url = url
        self.navegador = navegador
        self.rolEntrada = rolEntrada
        self.pistaEntrada = pistaEntrada
        self.teclaEnviar = teclaEnviar
        self.rolRespuesta = rolRespuesta
        self.esperaSegundos = esperaSegundos
        self.participaEnDebate = participaEnDebate
        self.mostrarCursor = mostrarCursor
        self.requiereRed = requiereRed
        self.color = color
        self.anclaX = anclaX
        self.anclaY = anclaY
    }

    public init?(_ valor: ValorJSON) {
        guard let mapa = valor.objeto else { return nil }
        let id = mapa["id"]?.texto ?? ""
        let nombre = mapa["nombre"]?.texto ?? id
        if id.isEmpty || nombre.isEmpty { return nil }
        self.init(
            id: id,
            nombre: nombre,
            tipo: mapa["tipo"]?.texto ?? "app",
            aplicacion: mapa["aplicacion"]?.texto ?? nombre,
            url: mapa["url"]?.texto ?? "",
            navegador: mapa["navegador"]?.texto ?? "Safari",
            rolEntrada: mapa["rol_entrada"]?.texto ?? "AXTextArea",
            pistaEntrada: mapa["pista_entrada"]?.texto ?? "",
            teclaEnviar: mapa["tecla_enviar"]?.texto ?? "return",
            rolRespuesta: mapa["rol_respuesta"]?.texto ?? "AXStaticText",
            esperaSegundos: mapa["espera_segundos"]?.numero ?? 40,
            participaEnDebate: mapa["participa_en_debate"]?.bool ?? true,
            mostrarCursor: mapa["mostrar_cursor"]?.bool ?? true,
            requiereRed: mapa["requiere_red"]?.bool ?? true,
            color: mapa["color"]?.texto ?? "#8E8E93",
            anclaX: mapa["ancla"]?.objeto?["x"]?.numero ?? 0.5,
            anclaY: mapa["ancla"]?.objeto?["y"]?.numero ?? 0.4
        )
    }

    public func comoAgente() -> AgenteConfig {
        var agente = AgenteConfig(
            id: id,
            nombre: nombre,
            color: color,
            rol: "Participas escribiendo en \(aplicacion) como lo haría una persona. No resuelvas captchas ni inicies sesión: si hace falta, pídeselo al usuario.",
            herramientas: ["operar_chat"],
            anclaX: anclaX,
            anclaY: anclaY
        )
        agente.modalidad = .gui
        agente.proveedor = .gui
        agente.modelo = id
        agente.requiereRed = requiereRed
        agente.debate = participaEnDebate
        return agente
    }

    public static func fusionar(integrados: [AdaptadorChat], archivo: [AdaptadorChat]) -> [AdaptadorChat] {
        var porID = Dictionary(uniqueKeysWithValues: integrados.map { ($0.id, $0) })
        for adaptador in archivo { porID[adaptador.id] = adaptador }
        let orden = integrados.map(\.id) + archivo.map(\.id).filter { id in !integrados.contains { $0.id == id } }
        var vistos = Set<String>()
        return orden.compactMap { id in
            guard vistos.insert(id).inserted else { return nil }
            return porID[id]
        }
    }

    public static let integrados: [AdaptadorChat] = [
        AdaptadorChat(id: "antigravity", nombre: "Antigravity", tipo: "app", aplicacion: "Antigravity", rolEntrada: "AXTextArea", pistaEntrada: "Ask", teclaEnviar: "return", requiereRed: false, color: "#7CFFB2", anclaX: 0.18, anclaY: 0.40),
        AdaptadorChat(id: "chatgpt", nombre: "ChatGPT", tipo: "app", aplicacion: "ChatGPT", url: "https://chatgpt.com", navegador: "Safari", rolEntrada: "AXTextArea", pistaEntrada: "Message", teclaEnviar: "return", requiereRed: true, color: "#74AA9C", anclaX: 0.34, anclaY: 0.18),
        AdaptadorChat(id: "claude", nombre: "Claude", tipo: "app", aplicacion: "Claude", url: "https://claude.ai", navegador: "Safari", rolEntrada: "AXTextArea", pistaEntrada: "Reply", teclaEnviar: "return", requiereRed: true, color: "#D4A27F", anclaX: 0.52, anclaY: 0.16),
        AdaptadorChat(id: "muse", nombre: "Muse", tipo: "web", aplicacion: "Safari", url: "https://meta.ai", navegador: "Safari", rolEntrada: "AXTextArea", pistaEntrada: "Ask", teclaEnviar: "return", requiereRed: true, color: "#0668E1", anclaX: 0.70, anclaY: 0.18),
        AdaptadorChat(id: "navegador", nombre: "Navegador", tipo: "web", aplicacion: "Safari", url: "", navegador: "Safari", rolEntrada: "AXTextField", pistaEntrada: "address", teclaEnviar: "return", participaEnDebate: false, requiereRed: true, color: "#C084FC", anclaX: 0.86, anclaY: 0.36),
    ]
}

public protocol OperadorChat: AnyObject {
    func preguntar(adaptador: AdaptadorChat, texto: String, alMover: @escaping @Sendable (PuntoNorm) -> Void) async -> String
}

public final class OperadorFijo: OperadorChat {
    public var respuestas: [String: String]
    public init(respuestas: [String: String] = [:]) { self.respuestas = respuestas }
    public func preguntar(adaptador: AdaptadorChat, texto: String, alMover: @escaping @Sendable (PuntoNorm) -> Void) async -> String {
        alMover(PuntoNorm(x: adaptador.anclaX, y: adaptador.anclaY))
        return respuestas[adaptador.id] ?? "\(adaptador.nombre) no está disponible en esta prueba."
    }
}
