import Foundation

public struct EntradaRegistro: Codable, Equatable, Sendable {
    public var fechaISO: String
    public var origen: String
    public var agente: String
    public var herramienta: String
    public var detalle: String
    public var resultado: String
    public var nivel: String

    public init(fechaISO: String = marcaDeTiempo(), origen: String, agente: String = "", herramienta: String = "", detalle: String, resultado: String = "", nivel: String = "info") {
        self.fechaISO = fechaISO
        self.origen = origen
        self.agente = agente
        self.herramienta = herramienta
        self.detalle = Redaccion.limpiar(detalle)
        self.resultado = Redaccion.limpiar(resultado)
        self.nivel = nivel
    }
}

public func marcaDeTiempo(_ fecha: Date = Date()) -> String {
    let formato = ISO8601DateFormatter()
    formato.formatOptions = [.withInternetDateTime]
    return formato.string(from: fecha)
}

public final class RegistroAcciones: @unchecked Sendable {
    public let archivo: URL
    private let lock = NSLock()

    public init(archivo: URL) throws {
        self.archivo = archivo
        let carpeta = archivo.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: archivo.path) {
            FileManager.default.createFile(atPath: archivo.path, contents: nil)
        }
    }

    public func anotar(_ entrada: EntradaRegistro) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard var datos = try? encoder.encode(entrada) else { return }
        datos.append(0x0A)
        lock.lock()
        defer { lock.unlock() }
        if let handle = try? FileHandle(forWritingTo: archivo) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: datos)
        }
    }

    public func recientes(_ n: Int) -> [EntradaRegistro] {
        lock.lock()
        let texto = (try? String(contentsOf: archivo, encoding: .utf8)) ?? ""
        lock.unlock()
        let lineas = texto.split(separator: "\n", omittingEmptySubsequences: true)
        let decoder = JSONDecoder()
        return lineas.suffix(n).compactMap { linea in
            try? decoder.decode(EntradaRegistro.self, from: Data(linea.utf8))
        }
    }

    public func textoReciente(_ n: Int) -> String {
        recientes(n).map { entrada in
            "\(entrada.fechaISO)  \(entrada.nivel)  \(entrada.agente)  \(entrada.herramienta)  \(entrada.detalle)  \(entrada.resultado)"
        }.joined(separator: "\n")
    }
}
