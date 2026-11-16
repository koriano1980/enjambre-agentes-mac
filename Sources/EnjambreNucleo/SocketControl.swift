import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum ClienteControl {
    /// Devuelve nil si no hay un enjambre escuchando.
    public static func enviar(ruta: String, mensaje: ValorJSON, tiempo: TimeInterval) -> ValorJSON? {
        let fd = abrirSocketUNIX()
        if fd < 0 { return nil }
        defer { close(fd) }
        aplicarTiempo(fd, tiempo: tiempo)
        guard var direccion = direccionUNIX(ruta) else { return nil }
        let conectado = withUnsafePointer(to: &direccion) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saptr in
                connect(fd, saptr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if conectado != 0 { return nil }
        let linea = mensaje.textoPlano + "\n"
        let bytes = Array(linea.utf8)
        var enviados = 0
        while enviados < bytes.count {
            let n = bytes[enviados...].withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return write(fd, base, raw.count)
            }
            if n <= 0 { return nil }
            enviados += n
        }
        var acumulado = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while acumulado.count < 1_000_000 {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            acumulado.append(buffer, count: n)
            if acumulado.contains(0x0A) { break }
        }
        guard let texto = String(data: acumulado, encoding: .utf8) else { return nil }
        let lineaRespuesta = texto.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return try? ValorJSON.parsear(lineaRespuesta)
    }
}

public final class ServidorControl {
    private var fdEscucha: Int32 = -1
    private var ruta = ""
    private let lock = NSLock()
    public var alMensaje: ((ValorJSON) async -> ValorJSON)?

    public init() {}

    public func iniciar(ruta: String) throws {
        try FileManager.default.createDirectory(at: URL(fileURLWithPath: ruta).deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: ruta) || accesoSocket(ruta) {
            if ClienteControl.enviar(ruta: ruta, mensaje: .objeto(["tipo": .texto("eco"), "texto": .texto("ping")]), tiempo: 0.3) != nil {
                throw ErrorFormato(mensaje: "Ya hay un Enjambre escuchando. Usa el que está en la barra de menú o `enjambre parar`.")
            }
            unlink(ruta)
        }
        let fd = abrirSocketUNIX()
        if fd < 0 { throw ErrorFormato(mensaje: "No se pudo abrir el socket de control") }
        guard var direccion = direccionUNIX(ruta) else {
            close(fd)
            throw ErrorFormato(mensaje: "La ruta del socket es demasiado larga: \(ruta)")
        }
        let resultado = withUnsafePointer(to: &direccion) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saptr in
                bind(fd, saptr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if resultado != 0 {
            close(fd)
            throw ErrorFormato(mensaje: "No pude reservar \(ruta) (errno \(errno))")
        }
        if listen(fd, 8) != 0 {
            close(fd)
            throw ErrorFormato(mensaje: "No pude escuchar en el socket de control")
        }
        _ = chmod(ruta, 0o600)
        lock.lock()
        fdEscucha = fd
        self.ruta = ruta
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.aceptar()
        }
    }

    public func detener() {
        lock.lock()
        let fd = fdEscucha
        let ruta = self.ruta
        fdEscucha = -1
        lock.unlock()
        if fd >= 0 { close(fd) }
        if !ruta.isEmpty { unlink(ruta) }
    }

    private func aceptar() {
        while true {
            lock.lock()
            let escucha = fdEscucha
            lock.unlock()
            if escucha < 0 { return }
            let cliente = accept(escucha, nil, nil)
            if cliente < 0 { return }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.atender(cliente)
            }
        }
    }

    private func atender(_ fd: Int32) {
        defer { close(fd) }
        var acumulado = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while acumulado.count < 65_536 {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            acumulado.append(buffer, count: n)
            if acumulado.contains(0x0A) { break }
        }
        let texto = String(data: acumulado, encoding: .utf8) ?? ""
        let linea = texto.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let semaforo = DispatchSemaphore(value: 0)
        let respuesta = RespuestaSocket()
        Task {
            let valor: ValorJSON
            if let mensaje = try? ValorJSON.parsear(linea), let alMensaje = self.alMensaje {
                valor = await alMensaje(mensaje)
            } else {
                valor = .objeto(["ok": .bool(false), "texto": .texto("Mensaje de control ilegible.")])
            }
            respuesta.fijar(valor)
            semaforo.signal()
        }
        _ = semaforo.wait(timeout: .now() + 900)
        let datos = Data((respuesta.valor.textoPlano + "\n").utf8)
        datos.withUnsafeBytes { raw in
            if let base = raw.baseAddress { _ = write(fd, base, raw.count) }
        }
    }
}

private final class RespuestaSocket: @unchecked Sendable {
    private let lock = NSLock()
    private var interno: ValorJSON = .objeto(["ok": .bool(false), "texto": .texto("Sin respuesta.")])
    func fijar(_ valor: ValorJSON) {
        lock.lock(); interno = valor; lock.unlock()
    }
    var valor: ValorJSON {
        lock.lock(); defer { lock.unlock() }
        return interno
    }
}

private func abrirSocketUNIX() -> Int32 {
    #if os(Linux)
    return socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
    #else
    return socket(AF_UNIX, SOCK_STREAM, 0)
    #endif
}

private func accesoSocket(_ ruta: String) -> Bool {
    var st = stat()
    return stat(ruta, &st) == 0
}

private func direccionUNIX(_ ruta: String) -> sockaddr_un? {
    var direccion = sockaddr_un()
    direccion.sun_family = sa_family_t(AF_UNIX)
    #if os(macOS)
    direccion.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    #endif
    let capacidad = MemoryLayout.size(ofValue: direccion.sun_path)
    var cabe = true
    withUnsafeMutablePointer(to: &direccion.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: capacidad) { cptr in
            memset(cptr, 0, capacidad)
            ruta.withCString { src in
                if strlen(src) >= capacidad { cabe = false; return }
                strncpy(cptr, src, capacidad - 1)
            }
        }
    }
    return cabe ? direccion : nil
}

private func aplicarTiempo(_ fd: Int32, tiempo: TimeInterval) {
    var tv = timeval()
    tv.tv_sec = time_t(max(0, tiempo))
    #if os(Linux)
    tv.tv_usec = suseconds_t(Int((tiempo - Double(tv.tv_sec)) * 1_000_000))
    #else
    tv.tv_usec = Int32((tiempo - Double(Int(tiempo))) * 1_000_000)
    #endif
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
}
