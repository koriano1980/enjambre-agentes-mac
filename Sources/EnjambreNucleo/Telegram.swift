import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct MensajeTelegram: Equatable, Sendable {
    public var updateID: Int64
    public var chatID: Int64
    public var texto: String

    public init(updateID: Int64, chatID: Int64, texto: String) {
        self.updateID = updateID
        self.chatID = chatID
        self.texto = texto
    }
}

public enum AnalizadorTelegram {
    public static func mensajes(json: ValorJSON) -> [MensajeTelegram] {
        guard json["ok"]?.bool == true, let lista = json["result"]?.lista else { return [] }
        return lista.compactMap { item in
            guard let update = item.entero("update_id") ?? item["update_id"]?.entero else { return nil }
            let mensaje = item["message"] ?? item["edited_message"]
            guard let chat = mensaje?["chat"]?["id"]?.entero else { return nil }
            let texto = mensaje?["text"]?.texto ?? ""
            if texto.isEmpty { return nil }
            return MensajeTelegram(updateID: update, chatID: chat, texto: texto)
        }
    }

    public static func siguienteOffset(_ mensajes: [MensajeTelegram], anterior: Int64) -> Int64 {
        guard let maximo = mensajes.map(\.updateID).max() else { return anterior }
        return maximo + 1
    }
}

public func respuestaAfirmativa(_ texto: String) -> Bool {
    let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return ["si", "sí", "yes", "ok", "permitir", "dale", "adelante"].contains(limpio)
}

actor BuzonTelegram {
    private var chat: Int64?
    private var continuacion: CheckedContinuation<String?, Never>?
    private var generacion = 0

    func esperar(chat esperado: Int64, nanos: UInt64) async -> String? {
        generacion += 1
        let generacionActual = generacion
        if let continuacion {
            continuacion.resume(returning: nil)
            self.continuacion = nil
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            self.chat = esperado
            self.continuacion = cont
            Task { await self.vencer(nanos: nanos, generacion: generacionActual) }
        }
    }

    func ofrecer(chat recibido: Int64, texto: String) -> Bool {
        guard chat == recibido, let continuacion else { return false }
        generacion += 1
        self.continuacion = nil
        self.chat = nil
        continuacion.resume(returning: texto)
        return true
    }

    private func vencer(nanos: UInt64, generacion esperada: Int) async {
        try? await Task.sleep(nanoseconds: nanos)
        guard generacion == esperada, let continuacion else { return }
        self.continuacion = nil
        self.chat = nil
        continuacion.resume(returning: nil)
    }
}

public final class PuenteTelegram {
    public var token: String
    public var chatsPermitidos: Set<Int64>
    public var alOrden: ((String, Int64) async -> String)?
    public var alParar: (() async -> Void)?
    public var alDemo: (() async -> Void)?
    public var alEstado: (() async -> String)?
    public var registro: RegistroAcciones?
    public var tiempoConfirmacion: TimeInterval
    public var chatGrupo: Int64 = 0
    public var alSugerencia: ((String, String) async -> Void)?
    private var tarea: Task<Void, Never>?
    private let buzon = BuzonTelegram()
    private var offset: Int64 = 0

    public init(token: String, chatsPermitidos: Set<Int64>, tiempoConfirmacion: TimeInterval = 45) {
        self.token = token
        self.chatsPermitidos = chatsPermitidos
        self.tiempoConfirmacion = tiempoConfirmacion
    }

    public func iniciar() {
        guard tarea == nil else { return }
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        tarea = Task { [weak self] in
            await self?.bucle()
        }
    }

    public func detener() {
        tarea?.cancel()
        tarea = nil
    }

    public func enviar(chatID: Int64, texto: String) async {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        let cuerpo = limpio.isEmpty ? "(sin respuesta)" : limpio
        var inicio = cuerpo.startIndex
        while inicio < cuerpo.endIndex {
            let fin = cuerpo.index(inicio, offsetBy: 3500, limitedBy: cuerpo.endIndex) ?? cuerpo.endIndex
            await post("sendMessage", cuerpo: .objeto([
                "chat_id": .entero(chatID),
                "text": .texto(String(cuerpo[inicio..<fin])),
            ]))
            inicio = fin
        }
    }

    public func preguntar(chatID: Int64, texto: String) async -> Bool {
        await enviar(chatID: chatID, texto: texto + "\n\nResponde SI para permitir o NO para denegar.")
        let nanos = UInt64(max(5, tiempoConfirmacion) * 1_000_000_000)
        guard let respuesta = await buzon.esperar(chat: chatID, nanos: nanos) else { return false }
        return respuestaAfirmativa(respuesta)
    }

    private func bucle() async {
        while !Task.isCancelled {
            do {
                var componentes = URLComponents()
                componentes.queryItems = [
                    URLQueryItem(name: "timeout", value: "25"),
                    URLQueryItem(name: "offset", value: String(offset)),
                ]
                let consulta = componentes.percentEncodedQuery ?? ""
                let json = try await get("getUpdates?\(consulta)")
                let mensajes = AnalizadorTelegram.mensajes(json: json)
                offset = AnalizadorTelegram.siguienteOffset(mensajes, anterior: offset)
                for mensaje in mensajes {
                    await despachar(mensaje)
                }
            } catch {
                if Task.isCancelled { break }
                anotar("Error de Telegram: \(Redaccion.limpiar(String(describing: error)).replacingOccurrences(of: token, with: "•••"))")
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func despachar(_ mensaje: MensajeTelegram) async {
        if await buzon.ofrecer(chat: mensaje.chatID, texto: mensaje.texto) { return }
        let texto = mensaje.texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if chatGrupo != 0, mensaje.chatID == chatGrupo {
            if texto.hasPrefix("/") { return }
            await alSugerencia?("Telegram", texto)
            return
        }
        let autorizado = chatsPermitidos.contains(mensaje.chatID)
        if !autorizado {
            if texto == "/id" || texto == "/start" || chatsPermitidos.isEmpty {
                await enviar(chatID: mensaje.chatID, texto: "Tu chat id es \(mensaje.chatID). Añádelo a telegram.chat_ids en la configuración. Hasta entonces no ejecuto órdenes.")
                anotar("Chat \(mensaje.chatID) aún no está autorizado.")
            } else {
                anotar("Ignoro el chat \(mensaje.chatID): no está en la lista.")
            }
            return
        }
        switch texto {
        case "/parar", "/stop":
            await alParar?()
            await enviar(chatID: mensaje.chatID, texto: "Parado. Los agentes se detuvieron.")
        case "/demo":
            await alDemo?()
            await enviar(chatID: mensaje.chatID, texto: "Modo demostración en el Mac.")
        case "/estado":
            let estado = await alEstado?() ?? "Sin estado."
            await enviar(chatID: mensaje.chatID, texto: estado)
        case "/ayuda", "/start":
            await enviar(chatID: mensaje.chatID, texto: "Envía una orden en español. /parar detiene a los agentes, /demo muestra los cursores, /estado resume, /id muestra este chat.")
        default:
            if texto.hasPrefix("/") {
                await enviar(chatID: mensaje.chatID, texto: "No conozco ese comando. /ayuda")
                return
            }
            guard let alOrden else {
                await enviar(chatID: mensaje.chatID, texto: "El enjambre no está listo para órdenes.")
                return
            }
            let respuesta = await alOrden(texto, mensaje.chatID)
            await enviar(chatID: mensaje.chatID, texto: respuesta)
        }
    }

    private func get(_ metodoYConsulta: String) async throws -> ValorJSON {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/\(metodoYConsulta)") else {
            throw ErrorCerebro.fallo("URL de Telegram inválida")
        }
        var peticion = URLRequest(url: url, timeoutInterval: 40)
        let (datos, respuesta) = try await URLSession.shared.data(for: peticion)
        let codigo = (respuesta as? HTTPURLResponse)?.statusCode ?? 0
        let texto = String(data: datos, encoding: .utf8) ?? ""
        guard (200..<300).contains(codigo) else {
            throw ErrorCerebro.fallo("Telegram HTTP \(codigo)")
        }
        return try ValorJSON.parsear(texto)
    }

    private func post(_ metodo: String, cuerpo: ValorJSON) async {
        guard let url = URL(string: "https://api.telegram.org/bot\(token)/\(metodo)") else { return }
        var peticion = URLRequest(url: url, timeoutInterval: 30)
        peticion.httpMethod = "POST"
        peticion.setValue("application/json", forHTTPHeaderField: "Content-Type")
        peticion.httpBody = cuerpo.datos()
        do {
            _ = try await URLSession.shared.data(for: peticion)
        } catch {
            anotar("No pude enviar a Telegram.")
        }
    }

    private func anotar(_ texto: String) {
        registro?.anotar(EntradaRegistro(origen: "telegram", detalle: texto, nivel: "remoto"))
    }
}

private extension ValorJSON {
    func entero(_ clave: String) -> Int64? { self[clave]?.entero }
}
