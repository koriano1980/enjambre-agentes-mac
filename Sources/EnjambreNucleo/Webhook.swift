import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct PeticionHTTP: Equatable, Sendable {
    public var metodo: String
    public var ruta: String
    public var cabeceras: [String: String]
    public var cuerpo: String
}

public enum WebhookHTTP {
    public static func parsear(_ crudo: String) -> PeticionHTTP? {
        guard let separador = crudo.range(of: "\r\n\r\n") ?? crudo.range(of: "\n\n") else { return nil }
        let cabeza = String(crudo[..<separador.lowerBound])
        let cuerpo = String(crudo[separador.upperBound...])
        let lineas = cabeza.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let primera = lineas.first else { return nil }
        let trozos = primera.split(separator: " ")
        guard trozos.count >= 2 else { return nil }
        var cabeceras: [String: String] = [:]
        for linea in lineas.dropFirst() {
            guard let dosPuntos = linea.firstIndex(of: ":") else { continue }
            let clave = linea[..<dosPuntos].trimmingCharacters(in: .whitespaces).lowercased()
            let valor = linea[linea.index(after: dosPuntos)...].trimmingCharacters(in: .whitespaces)
            cabeceras[clave] = valor
        }
        let longitud = Int(cabeceras["content-length"] ?? "") ?? cuerpo.utf8.count
        let cuerpoRecortado = String(cuerpo.prefix(longitud))
        return PeticionHTTP(metodo: String(trozos[0]).uppercased(), ruta: String(trozos[1]), cabeceras: cabeceras, cuerpo: cuerpoRecortado)
    }

    public static func autorizada(_ peticion: PeticionHTTP, secreto: String, ahora: Date = Date()) -> Bool {
        guard !secreto.isEmpty else { return false }
        let firma = peticion.cabeceras["x-enjambre-firma"] ?? ""
        if peticion.metodo == "POST" {
            return Cripto.firmaValida(secreto: secreto, mensaje: peticion.cuerpo, firmaHex: firma)
        }
        if peticion.metodo == "GET" {
            guard let marca = peticion.cabeceras["x-enjambre-tiempo"], let segundos = Double(marca) else { return false }
            if abs(ahora.timeIntervalSince1970 - segundos) > 60 { return false }
            return Cripto.firmaValida(secreto: secreto, mensaje: peticion.ruta + "\n" + marca, firmaHex: firma)
        }
        return false
    }

    public static func respuesta(codigo: Int, cuerpo: String) -> String {
        let texto = cuerpo
        return "HTTP/1.1 \(codigo) \(textoCodigo(codigo))\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(texto.utf8.count)\r\nConnection: close\r\n\r\n\(texto)"
    }

    private static func textoCodigo(_ codigo: Int) -> String {
        switch codigo {
        case 200: return "OK"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        default: return "Error"
        }
    }
}

public enum EntradaWebhook {
    /// Un mensaje externo es siempre una sugerencia. No contiene herramientas.
    public static func sugerencia(cuerpo: String) -> (autor: String, texto: String)? {
        guard let valor = try? ValorJSON.parsear(cuerpo), let texto = valor["texto"]?.texto, !texto.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        let autor = valor["autor"]?.texto?.trimmingCharacters(in: .whitespaces).nilSiVacioWebhook ?? "Externo"
        return (autor, texto)
    }
}

private extension String {
    var nilSiVacioWebhook: String? { isEmpty ? nil : self }
}

/// Endpoint JSON en texto plano. No sirve HTML ni ejecuta herramientas.
public final class ServidorWebhook {
    private var fd: Int32 = -1
    public var secreto: String
    public var mensajes: () -> [MensajeSala] = { [] }
    public var alSugerencia: ((String, String) -> Void)?
    public private(set) var puerto: Int = 0

    public init(secreto: String) { self.secreto = secreto }

    public func iniciar(puerto pedido: Int, exponerLAN: Bool) throws {
        let socketFD = socket(AF_INET, tipoStreamWebhook(), 0)
        if socketFD < 0 { throw ErrorFormato(mensaje: "No se pudo abrir el webhook") }
        var reutilizar: Int32 = 1
        _ = setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reutilizar, socklen_t(MemoryLayout<Int32>.size))
        var direccion = sockaddr_in()
        direccion.sin_family = sa_family_t(AF_INET)
        direccion.sin_port = UInt16(pedido).bigEndian
        direccion.sin_addr.s_addr = inet_addr(exponerLAN ? "0.0.0.0" : "127.0.0.1")
        let unido = withUnsafePointer(to: &direccion) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if unido != 0 || listen(socketFD, 8) != 0 {
            close(socketFD)
            throw ErrorFormato(mensaje: "No pude escuchar el webhook en el puerto \(pedido)")
        }
        fd = socketFD
        var real = sockaddr_in()
        var longitud = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &real) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketFD, $0, &longitud) }
        }
        puerto = Int(UInt16(bigEndian: real.sin_port))
        DispatchQueue.global(qos: .utility).async { [weak self] in self?.aceptar() }
    }

    public func detener() {
        let actual = fd
        fd = -1
        if actual >= 0 { close(actual) }
    }

    private func aceptar() {
        while fd >= 0 {
            let cliente = accept(fd, nil, nil)
            if cliente < 0 { return }
            DispatchQueue.global().async { [weak self] in self?.atender(cliente) }
        }
    }

    private func atender(_ cliente: Int32) {
        defer { close(cliente) }
        var datos = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while datos.count < 200_000 {
            let n = read(cliente, &buffer, buffer.count)
            if n <= 0 { break }
            datos.append(buffer, count: n)
            if let texto = String(data: datos, encoding: .utf8), texto.contains("\r\n\r\n") || texto.contains("\n\n") {
                if let peticion = WebhookHTTP.parsear(texto) {
                    let longitud = Int(peticion.cabeceras["content-length"] ?? "0") ?? 0
                    let cabeza = texto.range(of: "\r\n\r\n")?.upperBound ?? texto.range(of: "\n\n")?.upperBound
                    let ya = cabeza.map { texto.distance(from: $0, to: texto.endIndex) } ?? 0
                    if ya >= longitud { break }
                } else { break }
            }
        }
        let crudo = String(data: datos, encoding: .utf8) ?? ""
        guard let peticion = WebhookHTTP.parsear(crudo) else {
            responder(cliente, WebhookHTTP.respuesta(codigo: 400, cuerpo: #"{"ok":false,"texto":"petición ilegible"}"#))
            return
        }
        guard WebhookHTTP.autorizada(peticion, secreto: secreto) else {
            responder(cliente, WebhookHTTP.respuesta(codigo: 401, cuerpo: #"{"ok":false,"texto":"firma HMAC inválida"}"#))
            return
        }
        if peticion.metodo == "GET", peticion.ruta.hasPrefix("/v1/mensajes") {
            let lista = mensajes().suffix(80).map { mensaje in
                ValorJSON.objeto([
                    "id": .entero(Int64(mensaje.id)),
                    "autor": .texto(mensaje.autor),
                    "origen": .texto(mensaje.origen.rawValue),
                    "sugerencia": .bool(mensaje.sugerencia),
                    "texto": .texto(mensaje.texto),
                ])
            }
            let cuerpo = ValorJSON.objeto(["ok": .bool(true), "mensajes": .lista(Array(lista))]).textoPlano
            responder(cliente, WebhookHTTP.respuesta(codigo: 200, cuerpo: cuerpo))
            return
        }
        if peticion.metodo == "POST", peticion.ruta.hasPrefix("/v1/mensajes"), let sugerencia = EntradaWebhook.sugerencia(cuerpo: peticion.cuerpo) {
            alSugerencia?(sugerencia.autor, sugerencia.texto)
            responder(cliente, WebhookHTTP.respuesta(codigo: 200, cuerpo: #"{"ok":true,"sugerencia":true,"texto":"Quedó en el chat como sugerencia. No se ejecuta sola."}"#))
            return
        }
        responder(cliente, WebhookHTTP.respuesta(codigo: 404, cuerpo: #"{"ok":false,"texto":"solo /v1/mensajes"}"#))
    }

    private func responder(_ fd: Int32, _ texto: String) {
        let bytes = Array(texto.utf8)
        _ = bytes.withUnsafeBytes { raw in
            if let base = raw.baseAddress { write(fd, base, raw.count) }
        }
    }
}

private func tipoStreamWebhook() -> Int32 {
    #if os(Linux)
    return Int32(SOCK_STREAM.rawValue)
    #else
    return SOCK_STREAM
    #endif
}
