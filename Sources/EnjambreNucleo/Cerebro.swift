import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ErrorCerebro: Error, CustomStringConvertible, Equatable {
    case detenido
    case tiempo
    case fallo(String)
    case ejecutableNoEncontrado(String)

    public var description: String {
        switch self {
        case .detenido: return "Detenido por el interruptor."
        case .tiempo: return "El modelo tardó demasiado."
        case .fallo(let m): return m
        case .ejecutableNoEncontrado(let m): return "No encuentro el ejecutable «\(m)». ¿Está instalado Claude Code y has hecho claude /login?"
        }
    }
}

public protocol Cerebro: AnyObject {
    func completar(sistema: String, usuario: String) async throws -> String
}

public final class CerebroGuion: Cerebro {
    private let lock = NSLock()
    private var respuestas: [String]
    public private(set) var llamadas = 0

    public init(respuestas: [String]) { self.respuestas = respuestas }

    public func completar(sistema: String, usuario: String) async throws -> String {
        lock.lock()
        defer { lock.unlock() }
        llamadas += 1
        if respuestas.isEmpty {
            return #"{"herramienta":"terminar","argumentos":{"resumen":"Sin más guion."}}"#
        }
        return respuestas.removeFirst()
    }
}

public struct InvocacionClaude: Equatable, Sendable {
    public var argumentos: [String]
    public var entrada: String
    public init(argumentos: [String], entrada: String) {
        self.argumentos = argumentos
        self.entrada = entrada
    }
}

public struct OpcionesClaude: Equatable, Sendable {
    public var modelo: String
    public var soportaBare: Bool
    public var soportaTools: Bool
    public var soportaSlash: Bool
    public var soportaPermissionMode: Bool

    public init(modelo: String, soportaBare: Bool, soportaTools: Bool, soportaSlash: Bool, soportaPermissionMode: Bool) {
        self.modelo = modelo
        self.soportaBare = soportaBare
        self.soportaTools = soportaTools
        self.soportaSlash = soportaSlash
        self.soportaPermissionMode = soportaPermissionMode
    }
}

public enum AdaptadorClaudeCLI {
    public static func capacidades(desde ayuda: String) -> (bare: Bool, tools: Bool, slash: Bool, permiso: Bool) {
        (
            ayuda.contains("--bare"),
            ayuda.contains("--tools"),
            ayuda.contains("--disable-slash-commands"),
            ayuda.contains("--permission-mode")
        )
    }

    /// Deja el CLI en modo texto: sin herramientas nativas, para que solo el enjambre toque el Mac.
    public static func invocacion(opciones: OpcionesClaude, sistema: String, usuario: String) -> InvocacionClaude {
        var args = ["--print", "--output-format", "json", "--max-turns", "1", "--system-prompt", sistema]
        if opciones.soportaTools {
            args.append("--tools")
            args.append("")
        }
        if opciones.soportaBare { args.append("--bare") }
        if opciones.soportaSlash { args.append("--disable-slash-commands") }
        if opciones.soportaPermissionMode {
            args.append("--permission-mode")
            args.append("dontAsk")
        }
        if !opciones.modelo.trimmingCharacters(in: .whitespaces).isEmpty {
            args.append("--model")
            args.append(opciones.modelo)
        }
        return InvocacionClaude(argumentos: args, entrada: usuario)
    }

    public static func textoDeSalida(_ stdout: String) throws -> String {
        let limpio = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if limpio.isEmpty { throw ErrorCerebro.fallo("Claude no devolvió texto.") }
        let valor = (try? ValorJSON.parsear(limpio)) ?? ProtocoloAgente.extraerJSON(limpio)
        guard let objeto = valor?.objeto else { return limpio }
        if objeto["is_error"]?.bool == true {
            let mensaje = objeto["result"]?.texto ?? objeto["error"]?.texto ?? "Claude devolvió un error."
            throw ErrorCerebro.fallo(mensaje)
        }
        if let resultado = objeto["result"]?.texto {
            return resultado
        }
        if let resultado = objeto["result"] {
            return resultado.textoPlano
        }
        return limpio
    }
}

public enum BuscadorEjecutable {
    public static func resolver(nombre: String, rutaConfigurada: String, home: String, rutasExtra: [String], existe: (String) -> Bool) -> String? {
        let configurada = rutaConfigurada.trimmingCharacters(in: .whitespaces)
        if configurada.contains("/") {
            let expandida = RutasEnjambre.expandir(configurada, home: home)
            if existe(expandida) { return expandida }
            return nil
        }
        let base = configurada.isEmpty ? nombre : configurada
        var candidatos = rutasExtra
        candidatos.append(contentsOf: [
            "\(home)/.local/bin/\(base)",
            "/opt/homebrew/bin/\(base)",
            "/usr/local/bin/\(base)",
            "/usr/bin/\(base)",
        ])
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for carpeta in path.split(separator: ":") {
                candidatos.append("\(carpeta)/\(base)")
            }
        }
        return candidatos.first { existe($0) }
    }
}

public final class CerebroClaudeCLI: Cerebro {
    public var ruta: String
    public var modelo: String
    public var tiempoEspera: TimeInterval
    public var directorio: String
    public var interrupcion: Interrupcion
    public var vivos: ProcesosVivos
    private var opciones: OpcionesClaude?
    private let lock = NSLock()

    public init(ruta: String, modelo: String, tiempoEspera: TimeInterval, directorio: String, interrupcion: Interrupcion, vivos: ProcesosVivos) {
        self.ruta = ruta
        self.modelo = modelo
        self.tiempoEspera = tiempoEspera
        self.directorio = directorio
        self.interrupcion = interrupcion
        self.vivos = vivos
    }

    public func completar(sistema: String, usuario: String) async throws -> String {
        if await interrupcion.estaDetenido() { throw ErrorCerebro.detenido }
        let opciones = try asegurarOpciones()
        let invocacion = AdaptadorClaudeCLI.invocacion(opciones: opciones, sistema: sistema, usuario: usuario)
        let resultado = LanzadorProceso.ejecutar(
            ejecutable: ruta,
            argumentos: invocacion.argumentos,
            directorio: directorio,
            entrada: invocacion.entrada,
            entorno: entornoConRutasHabituales(home: NSHomeDirectory()),
            tiempoLimite: tiempoEspera,
            vivos: vivos
        )
        let detenidoAhora = await interrupcion.estaDetenido()
        if resultado.detenido || detenidoAhora { throw ErrorCerebro.detenido }
        if resultado.excedioTiempo { throw ErrorCerebro.tiempo }
        let crudo = resultado.salida.isEmpty ? resultado.error : resultado.salida
        if crudo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ErrorCerebro.fallo(resultado.error.isEmpty ? "Claude terminó con código \(resultado.codigo) sin texto." : resultado.error)
        }
        return try AdaptadorClaudeCLI.textoDeSalida(crudo)
    }

    private func asegurarOpciones() throws -> OpcionesClaude {
        lock.lock()
        if let opciones { lock.unlock(); return opciones }
        lock.unlock()
        let ayuda = LanzadorProceso.ejecutar(
            ejecutable: ruta,
            argumentos: ["--help"],
            directorio: directorio,
            tiempoLimite: 20,
            vivos: vivos
        )
        let texto = ayuda.salida + "\n" + ayuda.error
        if texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && ayuda.codigo != 0 {
            throw ErrorCerebro.ejecutableNoEncontrado(ruta)
        }
        let caps = AdaptadorClaudeCLI.capacidades(desde: texto)
        let nuevas = OpcionesClaude(modelo: modelo, soportaBare: caps.bare, soportaTools: caps.tools || texto.isEmpty, soportaSlash: caps.slash, soportaPermissionMode: caps.permiso)
        lock.lock()
        opciones = nuevas
        lock.unlock()
        return nuevas
    }
}

public enum CuerpoHTTP {
    public static func anthropic(modelo: String, sistema: String, usuario: String, maxTokens: Int = 2500) -> ValorJSON {
        .objeto([
            "model": .texto(modelo),
            "max_tokens": .entero(Int64(maxTokens)),
            "system": .texto(sistema),
            "messages": .lista([.objeto(["role": .texto("user"), "content": .texto(usuario)])]),
        ])
    }

    public static func ollama(modelo: String, sistema: String, usuario: String) -> ValorJSON {
        .objeto([
            "model": .texto(modelo),
            "stream": .bool(false),
            "keep_alive": .texto("90s"),
            "messages": .lista([
                .objeto(["role": .texto("system"), "content": .texto(sistema)]),
                .objeto(["role": .texto("user"), "content": .texto(usuario)]),
            ]),
        ])
    }

    public static func textoAnthropic(_ respuesta: ValorJSON) -> String? {
        respuesta["content"]?.lista?.first?["text"]?.texto
    }

    public static func textoOllama(_ respuesta: ValorJSON) -> String? {
        respuesta["message"]?["content"]?.texto
    }

    public static func compatible(modelo: String, sistema: String, usuario: String) -> ValorJSON {
        .objeto([
            "model": .texto(modelo),
            "messages": .lista([
                .objeto(["role": .texto("system"), "content": .texto(sistema)]),
                .objeto(["role": .texto("user"), "content": .texto(usuario)]),
            ]),
        ])
    }

    public static func textoCompatible(_ respuesta: ValorJSON) -> String? {
        respuesta["choices"]?.lista?.first?["message"]?["content"]?.texto
    }

    public static func gemini(sistema: String, usuario: String) -> ValorJSON {
        .objeto([
            "system_instruction": .objeto(["parts": .lista([.objeto(["text": .texto(sistema)])])]),
            "contents": .lista([.objeto(["role": .texto("user"), "parts": .lista([.objeto(["text": .texto(usuario)])])])]),
        ])
    }

    public static func textoGemini(_ respuesta: ValorJSON) -> String? {
        respuesta["candidates"]?.lista?.first?["content"]?["parts"]?.lista?.first?["text"]?.texto
    }
}

public final class CerebroAnthropic: Cerebro {
    public var clave: String
    public var modelo: String
    public var url: URL
    public var tiempo: TimeInterval
    public init(clave: String, modelo: String, url: URL = URL(string: "https://api.anthropic.com/v1/messages")!, tiempo: TimeInterval = 180) {
        self.clave = clave
        self.modelo = modelo
        self.url = url
        self.tiempo = tiempo
    }

    public func completar(sistema: String, usuario: String) async throws -> String {
        if clave.trimmingCharacters(in: .whitespaces).isEmpty {
            throw ErrorCerebro.fallo("Falta la clave de Anthropic. El enjambre local no la necesita; solo el agente que use anthropic-api.")
        }
        let cuerpo = CuerpoHTTP.anthropic(modelo: modelo.isEmpty ? "claude-sonnet-4-5" : modelo, sistema: sistema, usuario: usuario)
        let respuesta = try await ClienteHTTP.postJSON(url: url, cuerpo: cuerpo, cabeceras: [
            "x-api-key": clave,
            "anthropic-version": "2023-06-01",
        ], tiempo: tiempo)
        guard let texto = CuerpoHTTP.textoAnthropic(respuesta) else {
            throw ErrorCerebro.fallo("La API de Anthropic no devolvió texto: \(recortarTexto(respuesta.textoPlano, maximo: 500))")
        }
        return texto
    }
}

public final class CerebroOllama: Cerebro {
    public var modelo: String
    public var url: URL
    public var tiempo: TimeInterval
    public init(modelo: String, url: URL = URL(string: "http://127.0.0.1:11434/api/chat")!, tiempo: TimeInterval = 180) {
        self.modelo = modelo.isEmpty ? "llama3.1" : modelo
        self.url = url
        self.tiempo = tiempo
    }

    public func completar(sistema: String, usuario: String) async throws -> String {
        let cuerpo = CuerpoHTTP.ollama(modelo: modelo, sistema: sistema, usuario: usuario)
        let respuesta = try await ClienteHTTP.postJSON(url: url, cuerpo: cuerpo, cabeceras: [:], tiempo: tiempo)
        guard let texto = CuerpoHTTP.textoOllama(respuesta) else {
            throw ErrorCerebro.fallo("Ollama no devolvió texto. ¿Está arrancado en \(url.absoluteString)?")
        }
        return texto
    }
}

enum ClienteHTTP {
    static func postJSON(url: URL, cuerpo: ValorJSON, cabeceras: [String: String], tiempo: TimeInterval) async throws -> ValorJSON {
        var peticion = URLRequest(url: url, timeoutInterval: tiempo)
        peticion.httpMethod = "POST"
        peticion.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (clave, valor) in cabeceras { peticion.setValue(valor, forHTTPHeaderField: clave) }
        peticion.httpBody = cuerpo.datos()
        let (datos, respuesta) = try await URLSession.shared.data(for: peticion)
        let codigo = (respuesta as? HTTPURLResponse)?.statusCode ?? 0
        let texto = String(data: datos, encoding: .utf8) ?? ""
        guard (200..<300).contains(codigo) else {
            throw ErrorCerebro.fallo("HTTP \(codigo): \(recortarTexto(Redaccion.limpiar(texto), maximo: 400))")
        }
        return try ValorJSON.parsear(texto)
    }
}

public enum FabricaCerebro {
    public static func crear(config: Configuracion, home: String, interrupcion: Interrupcion, vivos: ProcesosVivos, directorioNeutral: String) -> Cerebro {
        switch config.cerebro.tipo {
        case .claudeCLI:
            let ruta = BuscadorEjecutable.resolver(
                nombre: "claude",
                rutaConfigurada: config.cerebro.ruta,
                home: home,
                rutasExtra: [],
                existe: { FileManager.default.isExecutableFile(atPath: $0) }
            ) ?? config.cerebro.ruta
            return CerebroClaudeCLI(
                ruta: ruta,
                modelo: config.cerebro.modelo,
                tiempoEspera: config.cerebro.tiempoEsperaSegundos,
                directorio: directorioNeutral,
                interrupcion: interrupcion,
                vivos: vivos
            )
        case .anthropic:
            return CerebroAnthropic(clave: config.cerebro.claveAPI, modelo: config.cerebro.modelo, tiempo: config.cerebro.tiempoEsperaSegundos)
        case .ollama:
            let textoURL = config.cerebro.url.isEmpty ? "http://127.0.0.1:11434/api/chat" : config.cerebro.url
            let url = URL(string: textoURL) ?? URL(string: "http://127.0.0.1:11434/api/chat")!
            return CerebroOllama(modelo: config.cerebro.modelo, url: url, tiempo: config.cerebro.tiempoEsperaSegundos)
        }
    }
}
