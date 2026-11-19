import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum ClienteNodo {
    public static func completar(host: String, puerto: Int, token: String, modelo: String, sistema: String, usuario: String) throws -> String {
        let mensaje = ValorJSON.objeto([
            "tipo": .texto("completar"),
            "token": .texto(token),
            "modelo": .texto(modelo),
            "sistema": .texto(sistema),
            "usuario": .texto(usuario),
        ])
        let respuesta = try enviar(host: host, puerto: puerto, mensaje: mensaje, tiempo: 180)
        if respuesta["ok"]?.bool == false {
            throw ErrorCerebro.fallo(respuesta["texto"]?.texto ?? "El nodo rechazó la petición.")
        }
        return respuesta["texto"]?.texto ?? ""
    }

    public static func eco(host: String, puerto: Int, token: String) -> Bool {
        let mensaje = ValorJSON.objeto(["tipo": .texto("hola"), "token": .texto(token)])
        guard let respuesta = try? enviar(host: host, puerto: puerto, mensaje: mensaje, tiempo: 2) else { return false }
        return respuesta["ok"]?.bool == true
    }

    static func enviar(host: String, puerto: Int, mensaje: ValorJSON, tiempo: TimeInterval) throws -> ValorJSON {
        let fd = socket(AF_INET, tipoStream(), 0)
        if fd < 0 { throw ErrorCerebro.fallo("No pude abrir la conexión con el nodo.") }
        defer { close(fd) }
        var destino = sockaddr_in()
        destino.sin_family = sa_family_t(AF_INET)
        destino.sin_port = puertoRed(UInt16(puerto))
        guard inet_pton(AF_INET, host, &destino.sin_addr) == 1 else {
            throw ErrorCerebro.fallo("Dirección de nodo inválida: \(host)")
        }
        let conectado = withUnsafePointer(to: &destino) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if conectado != 0 { throw ErrorCerebro.fallo("El nodo \(host):\(puerto) no acepta conexiones.") }
        try escribirLinea(fd, mensaje.textoPlano)
        let linea = leerLinea(fd, tiempo: tiempo)
        guard let valor = try? ValorJSON.parsear(linea) else {
            throw ErrorCerebro.fallo("Respuesta ilegible del nodo.")
        }
        return valor
    }
}

public final class ServidorNodo {
    private var fd: Int32 = -1
    public var token: String
    public var alCompletar: ((String, String, String) -> String)?
    public private(set) var puerto: Int = 0

    public init(token: String) { self.token = token }

    public func iniciar(puerto pedido: Int = 0) throws {
        let socketFD = socket(AF_INET, tipoStream(), 0)
        if socketFD < 0 { throw ErrorFormato(mensaje: "No se pudo abrir el puerto del nodo") }
        var reutilizar: Int32 = 1
        _ = setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reutilizar, socklen_t(MemoryLayout<Int32>.size))
        var direccion = sockaddr_in()
        direccion.sin_family = sa_family_t(AF_INET)
        direccion.sin_port = puertoRed(UInt16(pedido))
        direccion.sin_addr.s_addr = inet_addr("127.0.0.1")
        let unido = withUnsafePointer(to: &direccion) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if unido != 0 || listen(socketFD, 8) != 0 {
            close(socketFD)
            throw ErrorFormato(mensaje: "No pude escuchar el nodo local")
        }
        var real = sockaddr_in()
        var longitud = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &real) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(socketFD, $0, &longitud) }
        }
        fd = socketFD
        puerto = Int(puertoHost(real.sin_port))
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.aceptar() }
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
        let linea = leerLinea(cliente, tiempo: 5)
        guard let valor = try? ValorJSON.parsear(linea) else {
            try? escribirLinea(cliente, #"{"ok":false,"texto":"ilegible"}"#)
            return
        }
        if (valor["token"]?.texto ?? "") != token {
            try? escribirLinea(cliente, #"{"ok":false,"texto":"token"}"#)
            return
        }
        switch valor["tipo"]?.texto ?? "" {
        case "hola":
            try? escribirLinea(cliente, #"{"ok":true,"texto":"listo"}"#)
        case "completar":
            let texto = alCompletar?(valor["modelo"]?.texto ?? "", valor["sistema"]?.texto ?? "", valor["usuario"]?.texto ?? "") ?? ""
            let respuesta = ValorJSON.objeto(["ok": .bool(true), "texto": .texto(texto)])
            try? escribirLinea(cliente, respuesta.textoPlano)
        default:
            try? escribirLinea(cliente, #"{"ok":false,"texto":"el nodo solo responde modelos, no ejecuta órdenes"}"#)
        }
    }
}

private func tipoStream() -> Int32 {
    #if os(Linux)
    return Int32(SOCK_STREAM.rawValue)
    #else
    return SOCK_STREAM
    #endif
}

private func puertoRed(_ puerto: UInt16) -> in_port_t {
    puerto.bigEndian
}

private func puertoHost(_ puerto: in_port_t) -> UInt16 {
    UInt16(bigEndian: puerto)
}

private func escribirLinea(_ fd: Int32, _ texto: String) throws {
    let linea = texto + "\n"
    let bytes = Array(linea.utf8)
    var enviados = 0
    while enviados < bytes.count {
        let n = bytes[enviados...].withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return write(fd, base, raw.count)
        }
        if n <= 0 { throw ErrorCerebro.fallo("Se cortó la conexión con el nodo.") }
        enviados += n
    }
}

private func leerLinea(_ fd: Int32, tiempo: TimeInterval) -> String {
    var tv = timeval()
    tv.tv_sec = time_t(max(1, Int(tiempo)))
    #if os(Linux)
    tv.tv_usec = 0
    #else
    tv.tv_usec = 0
    #endif
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    var acumulado = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while acumulado.count < 2_000_000 {
        let n = read(fd, &buffer, buffer.count)
        if n <= 0 { break }
        acumulado.append(buffer, count: n)
        if acumulado.contains(0x0A) { break }
    }
    let texto = String(data: acumulado, encoding: .utf8) ?? ""
    return texto.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
}
