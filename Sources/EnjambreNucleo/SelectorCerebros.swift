import Foundation

public final class SelectorCerebros {
    public var config: Configuracion
    public var operador: OperadorChat?
    public var cola: ColaModelos
    public var interrupcion: Interrupcion
    public var vivos: ProcesosVivos
    public var directorioNeutral: String
    public var home: String
    public var nodos: [String: (host: String, puerto: Int)] = [:]
    public var tokenNodo: String = ""

    public init(config: Configuracion, cola: ColaModelos, interrupcion: Interrupcion, vivos: ProcesosVivos, directorioNeutral: String, home: String) {
        self.config = config
        self.cola = cola
        self.interrupcion = interrupcion
        self.vivos = vivos
        self.directorioNeutral = directorioNeutral
        self.home = home
    }

    public func completar(agente: AgenteConfig, sistema: String, usuario: String, enLinea: Bool, nodosVivos: Set<String>) async throws -> String {
        if await interrupcion.estaDetenido() { throw ErrorCerebro.detenido }
        switch MesaDebate.ruta(de: agente, enLinea: enLinea, nodosVivos: nodosVivos) {
        case .dormido(let motivo):
            throw ErrorCerebro.fallo("\(agente.nombre) está en pausa (\(motivo)).")
        case .gui(let id):
            guard let operador, let adaptador = config.adaptadores.first(where: { $0.id == id }) ?? config.adaptadores.first(where: { $0.nombre == agente.nombre }) else {
                throw ErrorCerebro.fallo("No hay operador de apps para \(agente.nombre). Ábrelo en el Mac.")
            }
            return await operador.preguntar(adaptador: adaptador, texto: usuario) { _ in }
        case .remoto(let nodo, let modelo):
            guard let destino = nodos[nodo] else { throw ErrorCerebro.fallo("No tengo la dirección del nodo \(nodo).") }
            return try ClienteNodo.completar(host: destino.host, puerto: destino.puerto, token: tokenNodo, modelo: modelo, sistema: sistema, usuario: usuario)
        case .local(let proveedor, let modelo, let memoria):
            try await cola.adquirir(clave: agente.claveModelo, memoriaGB: memoria)
            do {
                let texto = try await local(proveedor: proveedor, modelo: modelo, sistema: sistema, usuario: usuario)
                await cola.liberar(clave: agente.claveModelo)
                return texto
            } catch {
                await cola.liberar(clave: agente.claveModelo)
                throw error
            }
        case .nube(let proveedor, let modelo):
            return try await nube(proveedor: proveedor, modelo: modelo.isEmpty ? config.endpoint(proveedor).modelo : modelo, sistema: sistema, usuario: usuario)
        }
    }

    private func local(proveedor: ProveedorModelo, modelo: String, sistema: String, usuario: String) async throws -> String {
        switch proveedor {
        case .ollama:
            let base = config.endpoint(.ollama).url
            let url = URL(string: base.isEmpty ? "http://127.0.0.1:11434/api/chat" : base)!
            let cerebro = CerebroOllama(modelo: modelo, url: url, tiempo: config.cerebro.tiempoEsperaSegundos)
            return try await cerebro.completar(sistema: sistema, usuario: usuario)
        case .mlx, .llamacpp:
            let porDefecto = proveedor == .mlx ? "http://127.0.0.1:8080/v1/chat/completions" : "http://127.0.0.1:8081/v1/chat/completions"
            let textoURL = config.endpoint(proveedor).url
            return try await CerebroCompatible(url: URL(string: textoURL.isEmpty ? porDefecto : textoURL)!, clave: "", modelo: modelo, tiempo: config.cerebro.tiempoEsperaSegundos).completar(sistema: sistema, usuario: usuario)
        default:
            throw ErrorCerebro.fallo("\(proveedor.rawValue) no es un proveedor local.")
        }
    }

    private func nube(proveedor: ProveedorModelo, modelo: String, sistema: String, usuario: String) async throws -> String {
        let punto = config.endpoint(proveedor)
        switch proveedor {
        case .claudeCLI:
            let ruta = BuscadorEjecutable.resolver(nombre: "claude", rutaConfigurada: punto.ruta.isEmpty ? config.cerebro.ruta : punto.ruta, home: home, rutasExtra: [], existe: { FileManager.default.isExecutableFile(atPath: $0) }) ?? "claude"
            let cerebro = CerebroClaudeCLI(ruta: ruta, modelo: modelo, tiempoEspera: config.cerebro.tiempoEsperaSegundos, directorio: directorioNeutral, interrupcion: interrupcion, vivos: vivos)
            return try await cerebro.completar(sistema: sistema, usuario: usuario)
        case .anthropic:
            return try await CerebroAnthropic(clave: punto.clave, modelo: modelo, tiempo: config.cerebro.tiempoEsperaSegundos).completar(sistema: sistema, usuario: usuario)
        case .gemini:
            guard !punto.clave.isEmpty else { throw ErrorCerebro.fallo("Falta la clave de Gemini en proveedores.gemini.clave_api.") }
            let nombre = modelo.isEmpty ? "gemini-2.0-flash" : modelo
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(nombre):generateContent?key=\(punto.clave)")!
            let respuesta = try await ClienteHTTP.postJSON(url: url, cuerpo: CuerpoHTTP.gemini(sistema: sistema, usuario: usuario), cabeceras: [:], tiempo: config.cerebro.tiempoEsperaSegundos)
            guard let texto = CuerpoHTTP.textoGemini(respuesta) else { throw ErrorCerebro.fallo("Gemini no devolvió texto.") }
            return texto
        case .openai, .grok, .openrouter:
            guard !punto.clave.isEmpty else { throw ErrorCerebro.fallo("Falta la clave de \(proveedor.rawValue). Sin ella ese agente en línea no puede entrar.") }
            let porDefecto: String
            switch proveedor {
            case .grok: porDefecto = "https://api.x.ai/v1/chat/completions"
            case .openrouter: porDefecto = "https://openrouter.ai/api/v1/chat/completions"
            default: porDefecto = "https://api.openai.com/v1/chat/completions"
            }
            let url = URL(string: punto.url.isEmpty ? porDefecto : punto.url)!
            return try await CerebroCompatible(url: url, clave: punto.clave, modelo: modelo, tiempo: config.cerebro.tiempoEsperaSegundos).completar(sistema: sistema, usuario: usuario)
        default:
            throw ErrorCerebro.fallo("Proveedor no disponible: \(proveedor.rawValue)")
        }
    }
}

public final class CerebroCompatible: Cerebro {
    public var url: URL
    public var clave: String
    public var modelo: String
    public var tiempo: TimeInterval
    public init(url: URL, clave: String, modelo: String, tiempo: TimeInterval) {
        self.url = url
        self.clave = clave
        self.modelo = modelo
        self.tiempo = tiempo
    }

    public func completar(sistema: String, usuario: String) async throws -> String {
        var cabeceras: [String: String] = [:]
        if !clave.isEmpty { cabeceras["Authorization"] = "Bearer \(clave)" }
        let respuesta = try await ClienteHTTP.postJSON(url: url, cuerpo: CuerpoHTTP.compatible(modelo: modelo, sistema: sistema, usuario: usuario), cabeceras: cabeceras, tiempo: tiempo)
        guard let texto = CuerpoHTTP.textoCompatible(respuesta) else {
            throw ErrorCerebro.fallo("El modelo compatible no devolvió texto.")
        }
        return texto
    }
}
