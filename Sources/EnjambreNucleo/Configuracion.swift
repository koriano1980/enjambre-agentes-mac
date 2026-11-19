import Foundation

public enum TipoCerebro: String, Equatable, Sendable {
    case claudeCLI = "claude-cli"
    case anthropic = "anthropic-api"
    case ollama = "ollama"
}

public struct CerebroConfig: Equatable, Sendable {
    public var tipo: TipoCerebro
    public var ruta: String
    public var modelo: String
    public var claveAPI: String
    public var url: String
    public var maxPasos: Int
    public var maxParalelo: Int
    public var tiempoEsperaSegundos: Double
    public var adjuntarCapturas: Bool

    public static func porDefecto() -> CerebroConfig {
        CerebroConfig(
            tipo: .ollama,
            ruta: "claude",
            modelo: "",
            claveAPI: "",
            url: "",
            maxPasos: 8,
            maxParalelo: 3,
            tiempoEsperaSegundos: 180,
            adjuntarCapturas: false
        )
    }
}

public enum ModalidadAgente: String, Equatable, Sendable {
    case local
    case online
    case gui
}

public enum ProveedorModelo: String, Equatable, Sendable {
    case ollama
    case mlx
    case llamacpp
    case claudeCLI = "claude-cli"
    case openai
    case gemini
    case grok
    case openrouter
    case anthropic
    case gui
}

public struct AgenteConfig: Equatable, Sendable {
    public var id: String
    public var nombre: String
    public var color: String
    public var rol: String
    public var herramientas: [String]
    public var anclaX: Double
    public var anclaY: Double
    public var modalidad: ModalidadAgente = .local
    public var proveedor: ProveedorModelo = .ollama
    public var modelo: String = "auto"
    public var memoriaGB: Double = 0
    public var vision: Bool = false
    public var coordinador: Bool = false
    public var nodo: String = ""
    public var requiereRed: Bool = false
    public var debate: Bool = true

    public var claveModelo: String { "\(proveedor.rawValue)|\(modelo)|\(nodo)" }
}

public struct VozConfig: Equatable, Sendable {
    public var idioma: String
    public var sintetizarRespuestas: Bool
    public var reconocimientoEnDispositivo: Bool
    public var maxCaracteresHablados: Int

    public static func porDefecto() -> VozConfig {
        VozConfig(idioma: "es-ES", sintetizarRespuestas: true, reconocimientoEnDispositivo: true, maxCaracteresHablados: 400)
    }
}

public struct TelegramConfig: Equatable, Sendable {
    public var activo: Bool
    public var token: String
    public var chatIDs: [Int64]
    /// Grupo donde se espeja el chat. Los mensajes del grupo son sugerencias, no órdenes.
    public var chatGrupo: Int64 = 0

    public static func porDefecto() -> TelegramConfig {
        TelegramConfig(activo: false, token: "", chatIDs: [])
    }
}

public enum PoliticaAprobacion: String, Equatable, Sendable {
    case siempre
    case siDestructivo = "si-destructivo"
    case nunca
}

public struct DebateConfig: Equatable, Sendable {
    public var activo: Bool
    public var rondas: Int
    public var maxParticipantes: Int
    public var incluirGUI: Bool
    public var aprobar: PoliticaAprobacion
    public var tiempoAprobacionSegundos: Double

    public static func porDefecto() -> DebateConfig {
        DebateConfig(activo: true, rondas: 1, maxParticipantes: 4, incluirGUI: true, aprobar: .siDestructivo, tiempoAprobacionSegundos: 90)
    }
}

public struct HardwareConfig: Equatable, Sendable {
    public var preset: String
    public var presupuestoGB: Double

    public static func porDefecto() -> HardwareConfig {
        HardwareConfig(preset: "auto", presupuestoGB: 0)
    }
}

public struct WebhookConfig: Equatable, Sendable {
    public var activo: Bool
    public var secreto: String
    public var puerto: Int
    public var exponerLAN: Bool
    public var urlSalida: String

    public static func porDefecto() -> WebhookConfig {
        WebhookConfig(activo: false, secreto: "", puerto: 8765, exponerLAN: false, urlSalida: "")
    }
}

public struct NodoAnfitrionConfig: Equatable, Sendable {
    public var rol: String
    public var nombre: String
    public var puerto: Int
    public var token: String
    public var anfitrion: String

    public static func porDefecto() -> NodoAnfitrionConfig {
        NodoAnfitrionConfig(rol: "auto", nombre: "", puerto: 47831, token: "", anfitrion: "")
    }
}

public struct NodoRemotoConfig: Equatable, Sendable {
    public var nombre: String
    public var host: String
    public var puerto: Int
}

public struct ProveedorEndpoint: Equatable, Sendable {
    public var url: String
    public var clave: String
    public var modelo: String
    public var ruta: String

    public static func vacio() -> ProveedorEndpoint {
        ProveedorEndpoint(url: "", clave: "", modelo: "", ruta: "")
    }
}

public struct SeguridadConfig: Equatable, Sendable {
    public var confirmarDestructivo: Bool
    public var tiempoConfirmacionSegundos: Double
    public var rutasEscritura: [String]

    public static func porDefecto() -> SeguridadConfig {
        SeguridadConfig(confirmarDestructivo: true, tiempoConfirmacionSegundos: 45, rutasEscritura: ["~"])
    }
}

public struct InterfazConfig: Equatable, Sendable {
    public var atajoOrden: String
    public var atajoVoz: String
    public var atajoParar: String
    public var enjambreAlTerminar: Bool
    public var mostrarPanelAlEjecutar: Bool
    public var cursoresEnReposo: Bool

    public static func porDefecto() -> InterfazConfig {
        InterfazConfig(
            atajoOrden: "ctrl+alt+cmd+e",
            atajoVoz: "ctrl+alt+cmd+space",
            atajoParar: "ctrl+alt+cmd+k",
            enjambreAlTerminar: true,
            mostrarPanelAlEjecutar: true,
            cursoresEnReposo: false
        )
    }
}

public struct Atajo: Equatable, Sendable {
    public var control: Bool
    public var opcion: Bool
    public var comando: Bool
    public var mayusculas: Bool
    public var tecla: String

    public var descripcion: String {
        var partes: [String] = []
        if control { partes.append("⌃") }
        if opcion { partes.append("⌥") }
        if mayusculas { partes.append("⇧") }
        if comando { partes.append("⌘") }
        partes.append(teclaVisible)
        return partes.joined()
    }

    public var teclaVisible: String {
        switch tecla {
        case "space": return "Espacio"
        case "return": return "↩"
        case "escape": return "Esc"
        case "tab": return "Tab"
        default: return tecla.uppercased()
        }
    }

    /// `ctrl+alt+cmd+k`, `ctrl+alt+cmd+space`.
    public static func parsear(_ texto: String) -> Atajo? {
        let trozos = texto.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let ultima = trozos.last else { return nil }
        let mods = Set(trozos.dropLast())
        let tecla: String
        switch ultima {
        case "space", "espacio": tecla = "space"
        case "return", "enter", "intro": tecla = "return"
        case "esc", "escape": tecla = "escape"
        case "tab": tecla = "tab"
        default:
            guard ultima.count == 1, ultima.first?.isLetter == true || ultima.first?.isNumber == true else { return nil }
            tecla = ultima
        }
        return Atajo(
            control: mods.contains("ctrl") || mods.contains("control"),
            opcion: mods.contains("alt") || mods.contains("option") || mods.contains("opt") || mods.contains("opcion"),
            comando: mods.contains("cmd") || mods.contains("command") || mods.contains("meta"),
            mayusculas: mods.contains("shift") || mods.contains("mayus"),
            tecla: tecla
        )
    }
}

public struct Configuracion: Equatable, Sendable {
    public var cerebro: CerebroConfig
    public var agentes: [AgenteConfig]
    public var voz: VozConfig
    public var telegram: TelegramConfig
    public var seguridad: SeguridadConfig
    public var interfaz: InterfazConfig
    public var directorioTrabajo: String
    public var debate: DebateConfig = .porDefecto()
    public var hardware: HardwareConfig = .porDefecto()
    public var webhook: WebhookConfig = .porDefecto()
    public var nodo: NodoAnfitrionConfig = .porDefecto()
    public var nodos: [NodoRemotoConfig] = []
    public var proveedores: [String: ProveedorEndpoint] = [:]
    public var adaptadores: [AdaptadorChat] = AdaptadorChat.integrados

    public static func porDefecto() -> Configuracion {
        Configuracion(
            cerebro: .porDefecto(),
            agentes: agentesPorDefecto(),
            voz: .porDefecto(),
            telegram: .porDefecto(),
            seguridad: .porDefecto(),
            interfaz: .porDefecto(),
            directorioTrabajo: "~"
        )
    }

    public static func cargar(desde url: URL) throws -> Configuracion {
        let texto = try String(contentsOf: url, encoding: .utf8)
        let valor: ValorJSON
        if url.pathExtension.lowercased() == "json" {
            valor = try ValorJSON.parsear(texto)
        } else {
            valor = try YAMLMinimo.parsear(texto)
        }
        return try Configuracion.interpretar(valor)
    }

    public static func interpretar(_ valor: ValorJSON) throws -> Configuracion {
        guard let raiz = valor.objeto else {
            throw ErrorFormato(mensaje: "La configuración tiene que ser un mapa")
        }
        var base = Configuracion.porDefecto()
        if let cerebro = raiz["cerebro"]?.objeto {
            base.cerebro = interpretarCerebro(cerebro, base: base.cerebro)
        }
        if let lista = raiz["agentes"]?.lista {
            let agentes = lista.compactMap { interpretarAgente($0) }
            if !agentes.isEmpty { base.agentes = agentes }
        }
        if let voz = raiz["voz"]?.objeto {
            base.voz = interpretarVoz(voz, base: base.voz)
        }
        if let telegram = raiz["telegram"]?.objeto {
            base.telegram = interpretarTelegram(telegram, base: base.telegram)
        }
        if let seguridad = raiz["seguridad"]?.objeto {
            base.seguridad = interpretarSeguridad(seguridad, base: base.seguridad)
        }
        if let interfaz = raiz["interfaz"]?.objeto {
            base.interfaz = interpretarInterfaz(interfaz, base: base.interfaz)
        }
        if let directorio = raiz["directorio_trabajo"]?.texto, !directorio.isEmpty {
            base.directorioTrabajo = directorio
        }
        if let debate = raiz["debate"]?.objeto {
            base.debate = interpretarDebate(debate, base: base.debate)
        }
        if let hardware = raiz["hardware"]?.objeto {
            base.hardware = interpretarHardware(hardware, base: base.hardware)
        }
        if let webhook = raiz["webhook"]?.objeto {
            base.webhook = interpretarWebhook(webhook, base: base.webhook)
        }
        if let nodo = raiz["nodo"]?.objeto {
            base.nodo = interpretarNodo(nodo, base: base.nodo)
        }
        if let nodos = raiz["nodos"]?.lista {
            base.nodos = nodos.compactMap { item in
                guard let mapa = item.objeto, let nombre = mapa["nombre"]?.texto else { return nil }
                return NodoRemotoConfig(nombre: nombre, host: mapa["host"]?.texto ?? "", puerto: Int(mapa["puerto"]?.entero ?? Int64(base.nodo.puerto)))
            }
        }
        if let proveedores = raiz["proveedores"]?.objeto {
            var mapa: [String: ProveedorEndpoint] = base.proveedores
            for (clave, valor) in proveedores {
                guard let obj = valor.objeto else { continue }
                mapa[clave] = ProveedorEndpoint(
                    url: obj["url"]?.texto ?? "",
                    clave: obj["clave_api"]?.texto ?? "",
                    modelo: obj["modelo"]?.texto ?? "",
                    ruta: obj["ruta"]?.texto ?? ""
                )
            }
            base.proveedores = mapa
        }
        if let adaptadores = raiz["adaptadores"]?.lista {
            let cargados = adaptadores.compactMap { AdaptadorChat($0) }
            if !cargados.isEmpty { base.adaptadores = AdaptadorChat.fusionar(integrados: base.adaptadores, archivo: cargados) }
        }
        return base
    }

    public static func cargarCompleta(desde url: URL) throws -> Configuracion {
        var config = try cargar(desde: url)
        let hermana = url.deletingLastPathComponent().appendingPathComponent("adaptadores.yaml")
        if FileManager.default.fileExists(atPath: hermana.path) {
            let texto = try String(contentsOf: hermana, encoding: .utf8)
            let valor = try YAMLMinimo.parsear(texto)
            let lista = valor["adaptadores"]?.lista ?? valor.lista ?? []
            let cargados = lista.compactMap { AdaptadorChat($0) }
            if !cargados.isEmpty {
                config.adaptadores = AdaptadorChat.fusionar(integrados: AdaptadorChat.integrados, archivo: cargados)
            }
        }
        return config
    }

    public func aplicando(gigabytes: Double) -> Configuracion {
        var copia = self
        let preset = PresetsHardware.elegir(gigabytes: gigabytes, forzado: hardware.preset)
        copia.hardware.preset = preset.id
        if hardware.presupuestoGB <= 0 {
            copia.hardware.presupuestoGB = preset.presupuestoGB
        }
        copia.agentes = agentes.map { agente in
            guard agente.modelo == "auto" || agente.modelo.isEmpty, agente.modalidad == .local, agente.proveedor != .gui else { return agente }
            guard let modelo = preset.modelos[agente.id] else { return agente }
            var ajustado = agente
            ajustado.modelo = modelo.nombre
            ajustado.proveedor = modelo.proveedor
            ajustado.memoriaGB = modelo.memoriaGB
            ajustado.vision = modelo.vision || agente.vision
            return ajustado
        }
        return copia
    }

    public func agentesVisibles() -> [AgenteConfig] {
        var lista = agentes
        for adaptador in adaptadores where adaptador.mostrarCursor {
            if lista.contains(where: { $0.id == adaptador.id }) { continue }
            lista.append(adaptador.comoAgente())
        }
        return lista
    }

    public func endpoint(_ proveedor: ProveedorModelo) -> ProveedorEndpoint {
        proveedores[proveedor.rawValue] ?? proveedores[aliasProveedor(proveedor)] ?? .vacio()
    }

    public func agente(id: String) -> AgenteConfig? {
        agentes.first { $0.id == id }
    }

    public func resolverAgente(id: String) -> AgenteConfig {
        if let exacto = agente(id: id) { return exacto }
        let buscado = id.lowercased()
        if let parecido = agentes.first(where: { $0.nombre.lowercased() == buscado || $0.id.lowercased() == buscado }) {
            return parecido
        }
        return agentes[0]
    }
}

public func agentesPorDefecto() -> [AgenteConfig] {
    [
        AgenteConfig(id: "coordinador", nombre: "Coordinador", color: "#E8F27A", rol: "Moderas el debate, partes la orden y fusionas el resultado. No ejecutas acciones destructivas.", herramientas: ["leer_archivo", "listar"], anclaX: 0.12, anclaY: 0.22, coordinador: true),
        AgenteConfig(id: "programador", nombre: "Programador", color: "#3DDC97", rol: "Ingeniero de software. Editas código, ejecutas pruebas y puedes pedirle a Antigravity que revise.", herramientas: ["shell", "leer_archivo", "escribir_archivo", "editar_archivo", "listar", "abrir", "operar_chat"], anclaX: 0.28, anclaY: 0.62),
        AgenteConfig(id: "archivos", nombre: "Archivos", color: "#FFB020", rol: "Organizas y buscas archivos. Pides confirmación antes de borrar.", herramientas: ["shell", "leer_archivo", "escribir_archivo", "listar", "abrir", "osascript"], anclaX: 0.48, anclaY: 0.74),
        AgenteConfig(id: "escritor", nombre: "Escritor", color: "#FF7AB2", rol: "Redactas en español claro.", herramientas: ["leer_archivo", "escribir_archivo", "editar_archivo", "listar", "teclado"], anclaX: 0.66, anclaY: 0.58),
        AgenteConfig(id: "ojos", nombre: "Ojos", color: "#7EE0D6", rol: "Miras la pantalla con un modelo de visión local y lees la interfaz.", herramientas: ["captura", "ui_arbol", "operar_chat", "raton", "teclado", "esperar"], anclaX: 0.84, anclaY: 0.70, vision: true),
        AgenteConfig(id: "investigador", nombre: "Investigador", color: "#5B8CFF", rol: "Investigas con un modelo en la nube cuando hay internet. Si no hay red, te retiras.", herramientas: ["shell", "leer_archivo", "listar", "abrir", "captura"], anclaX: 0.40, anclaY: 0.30, modalidad: .online, proveedor: .claudeCLI, modelo: "", requiereRed: true),
    ]
}

private func aliasProveedor(_ proveedor: ProveedorModelo) -> String {
    switch proveedor {
    case .claudeCLI: return "claude"
    default: return proveedor.rawValue
    }
}

private func interpretarCerebro(_ mapa: [String: ValorJSON], base: CerebroConfig) -> CerebroConfig {
    var c = base
    if let tipo = mapa["tipo"]?.texto, let valor = TipoCerebro(rawValue: tipo) {
        c.tipo = valor
    }
    if let ruta = mapa["ruta"]?.texto { c.ruta = ruta }
    if let modelo = mapa["modelo"]?.texto { c.modelo = modelo }
    if let clave = mapa["clave_api"]?.texto { c.claveAPI = clave }
    if let url = mapa["url"]?.texto { c.url = url }
    if let pasos = mapa["max_pasos"]?.entero { c.maxPasos = max(1, Int(pasos)) }
    if let paralelo = mapa["max_paralelo"]?.entero { c.maxParalelo = max(1, Int(paralelo)) }
    if let tiempo = mapa["tiempo_espera_segundos"]?.numero { c.tiempoEsperaSegundos = max(5, tiempo) }
    if let capturas = mapa["adjuntar_capturas"]?.bool { c.adjuntarCapturas = capturas }
    return c
}

private func interpretarAgente(_ valor: ValorJSON) -> AgenteConfig? {
    guard let mapa = valor.objeto else { return nil }
    let nombre = mapa["nombre"]?.texto ?? "Agente"
    let id = mapa["id"]?.texto?.trimmingCharacters(in: .whitespaces).nilSiVacio ?? identificador(nombre)
    let color = mapa["color"]?.texto?.nilSiVacio ?? "#8E8E93"
    let rol = mapa["rol"]?.texto ?? ""
    let herramientas = (mapa["herramientas"]?.lista ?? []).compactMap(\.texto)
    let ancla = mapa["ancla"]?.objeto
    let x = min(1, max(0, ancla?["x"]?.numero ?? 0.5))
    let y = min(1, max(0, ancla?["y"]?.numero ?? 0.5))
    var agente = AgenteConfig(id: id, nombre: nombre, color: color, rol: rol, herramientas: herramientas.isEmpty ? nombresDeHerramientas : herramientas, anclaX: x, anclaY: y)
    if let modalidad = mapa["modalidad"]?.texto, let valor = ModalidadAgente(rawValue: modalidad) { agente.modalidad = valor }
    if let proveedor = mapa["proveedor"]?.texto, let valor = ProveedorModelo(rawValue: proveedor) { agente.proveedor = valor }
    if let modelo = mapa["modelo"]?.texto { agente.modelo = modelo }
    if let memoria = mapa["memoria_gb"]?.numero { agente.memoriaGB = memoria }
    if let vision = mapa["vision"]?.bool { agente.vision = vision }
    if let coordinador = mapa["coordinador"]?.bool { agente.coordinador = coordinador }
    if let nodo = mapa["nodo"]?.texto { agente.nodo = nodo }
    if let red = mapa["requiere_red"]?.bool { agente.requiereRed = red }
    if let debate = mapa["debate"]?.bool { agente.debate = debate }
    if agente.modalidad == .online { agente.requiereRed = true }
    return agente
}

private func interpretarVoz(_ mapa: [String: ValorJSON], base: VozConfig) -> VozConfig {
    var v = base
    if let idioma = mapa["idioma"]?.texto, !idioma.isEmpty { v.idioma = idioma }
    if let s = mapa["sintetizar_respuestas"]?.bool { v.sintetizarRespuestas = s }
    if let r = mapa["reconocimiento_en_dispositivo"]?.bool { v.reconocimientoEnDispositivo = r }
    if let m = mapa["max_caracteres_hablados"]?.entero { v.maxCaracteresHablados = max(40, Int(m)) }
    return v
}

private func interpretarTelegram(_ mapa: [String: ValorJSON], base: TelegramConfig) -> TelegramConfig {
    var t = base
    if let activo = mapa["activo"]?.bool { t.activo = activo }
    if let token = mapa["token"]?.texto { t.token = token }
    if let lista = mapa["chat_ids"]?.lista {
        t.chatIDs = lista.compactMap(\.entero)
    }
    if let grupo = mapa["chat_grupo"]?.entero { t.chatGrupo = grupo }
    return t
}

private func interpretarDebate(_ mapa: [String: ValorJSON], base: DebateConfig) -> DebateConfig {
    var d = base
    if let a = mapa["activo"]?.bool { d.activo = a }
    if let r = mapa["rondas"]?.entero { d.rondas = max(1, Int(r)) }
    if let m = mapa["max_participantes"]?.entero { d.maxParticipantes = max(1, Int(m)) }
    if let g = mapa["incluir_gui"]?.bool { d.incluirGUI = g }
    if let p = mapa["aprobar"]?.texto, let valor = PoliticaAprobacion(rawValue: p) { d.aprobar = valor }
    if let t = mapa["tiempo_aprobacion_segundos"]?.numero { d.tiempoAprobacionSegundos = max(5, t) }
    return d
}

private func interpretarHardware(_ mapa: [String: ValorJSON], base: HardwareConfig) -> HardwareConfig {
    var h = base
    if let p = mapa["preset"]?.texto, !p.isEmpty { h.preset = p }
    if let g = mapa["presupuesto_gb"]?.numero { h.presupuestoGB = g }
    return h
}

private func interpretarWebhook(_ mapa: [String: ValorJSON], base: WebhookConfig) -> WebhookConfig {
    var w = base
    if let a = mapa["activo"]?.bool { w.activo = a }
    if let s = mapa["secreto"]?.texto { w.secreto = s }
    if let p = mapa["puerto"]?.entero { w.puerto = Int(p) }
    if let e = mapa["exponer_lan"]?.bool { w.exponerLAN = e }
    if let u = mapa["url_salida"]?.texto { w.urlSalida = u }
    return w
}

private func interpretarNodo(_ mapa: [String: ValorJSON], base: NodoAnfitrionConfig) -> NodoAnfitrionConfig {
    var n = base
    if let r = mapa["rol"]?.texto { n.rol = r }
    if let nombre = mapa["nombre"]?.texto { n.nombre = nombre }
    if let p = mapa["puerto"]?.entero { n.puerto = Int(p) }
    if let t = mapa["token"]?.texto { n.token = t }
    if let a = mapa["anfitrion"]?.texto { n.anfitrion = a }
    return n
}

private func interpretarSeguridad(_ mapa: [String: ValorJSON], base: SeguridadConfig) -> SeguridadConfig {
    var s = base
    if let c = mapa["confirmar_destructivo"]?.bool { s.confirmarDestructivo = c }
    if let t = mapa["tiempo_confirmacion_segundos"]?.numero { s.tiempoConfirmacionSegundos = max(5, t) }
    if let rutas = mapa["rutas_escritura"]?.lista {
        let textos = rutas.compactMap(\.texto).filter { !$0.isEmpty }
        if !textos.isEmpty { s.rutasEscritura = textos }
    }
    return s
}

private func interpretarInterfaz(_ mapa: [String: ValorJSON], base: InterfazConfig) -> InterfazConfig {
    var i = base
    if let a = mapa["atajo_orden"]?.texto { i.atajoOrden = a }
    if let a = mapa["atajo_voz"]?.texto { i.atajoVoz = a }
    if let a = mapa["atajo_parar"]?.texto { i.atajoParar = a }
    if let e = mapa["enjambre_al_terminar"]?.bool { i.enjambreAlTerminar = e }
    if let m = mapa["mostrar_panel_al_ejecutar"]?.bool { i.mostrarPanelAlEjecutar = m }
    if let c = mapa["cursores_en_reposo"]?.bool { i.cursoresEnReposo = c }
    return i
}

private func identificador(_ nombre: String) -> String {
    let base = nombre.lowercased().map { caracter -> Character in
        if caracter.isLetter || caracter.isNumber { return caracter }
        return "-"
    }
    let texto = String(base).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return texto.isEmpty ? "agente" : texto
}

private extension String {
    var nilSiVacio: String? { isEmpty ? nil : self }
}

public let nombresDeHerramientas = [
    "shell", "leer_archivo", "escribir_archivo", "editar_archivo", "listar", "esperar",
    "osascript", "abrir", "raton", "teclado", "captura", "ui_arbol", "operar_chat",
]
