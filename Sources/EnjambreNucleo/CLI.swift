import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum ModoArranque: Equatable {
    case ayuda
    case version
    case demo(segundos: Double, json: Bool, sinVentana: Bool, config: String?)
    case orden(String, config: String?)
    case comprobar(config: String?)
    case parar
    case interfaz(demo: Bool, config: String?)
}

public func interpretarArgumentos(_ args: [String]) -> ModoArranque {
    var indice = 1
    var config: String?
    var sinVentana = false
    var json = false
    var segundos = 8.0
    var demoFlag = false
    var posicionales: [String] = []
    while indice < args.count {
        let arg = args[indice]
        switch arg {
        case "-h", "--help", "ayuda", "help":
            return .ayuda
        case "--version", "version", "-v":
            return .version
        case "--config":
            indice += 1
            if indice < args.count { config = args[indice] }
        case "--sin-ventana", "--headless":
            sinVentana = true
        case "--json":
            json = true
        case "--segundos":
            indice += 1
            if indice < args.count, let valor = Double(args[indice]) { segundos = valor }
        case "--demo":
            demoFlag = true
        case "--parar", "parar":
            return .parar
        default:
            posicionales.append(arg)
        }
        indice += 1
    }
    if posicionales.isEmpty {
        if demoFlag { return .demo(segundos: segundos, json: json, sinVentana: sinVentana, config: config) }
        return .interfaz(demo: false, config: config)
    }
    switch posicionales[0] {
    case "demo":
        return .demo(segundos: segundos, json: json, sinVentana: sinVentana, config: config)
    case "orden":
        let texto = posicionales.dropFirst().joined(separator: " ")
        return .orden(texto, config: config)
    case "comprobar":
        return .comprobar(config: config)
    case "parar":
        return .parar
    default:
        return .orden(posicionales.joined(separator: " "), config: config)
    }
}

public enum CLINucleo {
    public static func ayuda() -> String {
        """
        Enjambre de Agentes \(versionEnjambre)
        Agentes locales y, si hay internet, agentes en la nube. Los cursores se ven en pantalla.
        Solo actúan cuando tú das la orden. El modo demo no necesita modelos.

          enjambre                      abre la barra de menú (macOS)
          enjambre demo                 anima los cursores, sin Claude
          enjambre demo --sin-ventana   imprime el guion (sirve para probar)
          enjambre orden "texto"        envía una orden al enjambre que ya está abierto
          enjambre comprobar            revisa configuración y el ejecutable de Claude
          enjambre parar                detiene a los agentes al instante
          enjambre ayuda

        Atajos por defecto: ⌃⌥⌘E orden, ⌃⌥⌘Espacio voz, ⌃⌥⌘K parar.
        """
    }

    public static func textoDemo(segundos: Double, json: Bool, agentes: [AgenteConfig]) -> String {
        let duracion = max(0.2, segundos)
        var muestras: [ValorJSON] = []
        var texto = ""
        var t = 0.0
        while t <= duracion + 0.001 {
            let escena = DemoGuion.escena(tiempo: t, agentes: agentes)
            if json {
                muestras.append(.objeto([
                    "t": .numero(t),
                    "aviso": .texto(escena.aviso ?? ""),
                    "cursores": .entero(Int64(escena.cursores.count)),
                ]))
            } else {
                texto += String(format: "t=%.1f  cursores=%d  %@\n", t, escena.cursores.count, escena.aviso ?? "")
            }
            t += 0.5
        }
        if json { return ValorJSON.lista(muestras).textoPlano }
        return texto
    }

    public static func comprobar(config: Configuracion, rutaConfig: String?, home: String) -> String {
        var lineas: [String] = []
        lineas.append("Enjambre de Agentes \(versionEnjambre)")
        lineas.append(rutaConfig == nil ? "Configuración: valores de fábrica (no encontré un archivo)." : "Configuración: \(rutaConfig!)")
        let efectiva = config.aplicando(gigabytes: MemoriaEquipo.gigabytes())
        lineas.append(String(format: "RAM detectada: %.0f GB · preset %@ · tope de modelos %.0f GB", MemoriaEquipo.gigabytes(), efectiva.hardware.preset, efectiva.hardware.presupuestoGB))
        lineas.append("Modelos locales: " + efectiva.agentes.filter { $0.modalidad == .local }.map { "\($0.nombre)=\($0.modelo)" }.joined(separator: ", "))
        lineas.append("Debate: \(efectiva.debate.activo ? "sí, moderado por el coordinador local" : "no")")
        lineas.append("Webhook de agentes externos: \(efectiva.webhook.activo ? "activo en el puerto \(efectiva.webhook.puerto)" : "apagado")")
        lineas.append("Cerebro de respaldo: \(config.cerebro.tipo.rawValue)")
        if let ruta = BuscadorEjecutable.resolver(nombre: "claude", rutaConfigurada: config.endpoint(.claudeCLI).ruta.isEmpty ? "claude" : config.endpoint(.claudeCLI).ruta, home: home, rutasExtra: [], existe: { FileManager.default.isExecutableFile(atPath: $0) }) {
            lineas.append("Claude Code (solo el agente en línea, con tu suscripción): \(ruta)")
        } else {
            lineas.append("Claude Code no está en el PATH. El investigador en línea no podrá usarlo hasta que hagas `claude` e inicies sesión. El resto del enjambre es local.")
        }
        lineas.append("Ollama (local, sin coste): \(config.endpoint(.ollama).url.isEmpty ? "http://127.0.0.1:11434" : config.endpoint(.ollama).url)")
        lineas.append("Agentes: " + config.agentes.map(\.nombre).joined(separator: ", "))
        lineas.append("Confirmación de acciones destructivas: \(config.seguridad.confirmarDestructivo ? "sí" : "no (el rechazo de borrados catastróficos sigue activo)")")
        lineas.append("Rutas de escritura: " + config.seguridad.rutasEscritura.joined(separator: ", "))
        if config.telegram.activo {
            let chats = config.telegram.chatIDs.isEmpty ? "ninguno (no se aceptan órdenes)" : config.telegram.chatIDs.map(String.init).joined(separator: ", ")
            lineas.append("Telegram: activo. Token \(config.telegram.token.isEmpty ? "vacío" : "presente"). Chats: \(chats).")
        } else {
            lineas.append("Telegram: apagado.")
        }
        lineas.append("Registro: \(RutasEnjambre.registro(home: home))")
        lineas.append("Atajo de parada: \(Atajo.parsear(config.interfaz.atajoParar)?.descripcion ?? config.interfaz.atajoParar)")
        return lineas.joined(separator: "\n")
    }

    public static func cargarConfiguracion(explicita: String?, home: String) -> (Configuracion, String?) {
        let cwd = FileManager.default.currentDirectoryPath
        let ruta = RutasEnjambre.buscarConfiguracion(explicita: explicita, directorio: cwd, home: home, existe: { FileManager.default.fileExists(atPath: $0) })
        guard let ruta else { return (.porDefecto(), nil) }
        do {
            return (try Configuracion.cargarCompleta(desde: URL(fileURLWithPath: ruta)), ruta)
        } catch {
            fputs("No pude leer \(ruta): \(error). Sigo con la configuración de fábrica.\n", stderr)
            return (.porDefecto(), ruta)
        }
    }

    public static func ejecutar(_ modo: ModoArranque, home: String = RutasEnjambre.homeActual(), salida: (String) -> Void = { print($0) }) async -> Int32 {
        switch modo {
        case .ayuda:
            salida(ayuda())
            return 0
        case .version:
            salida(versionEnjambre)
            return 0
        case .demo(let segundos, let json, _, let explicita):
            let (config, _) = cargarConfiguracion(explicita: explicita, home: home)
            if CommandLine.arguments.contains("--trazas") {
                salida(DemoGuion.trazaJSON(segundos: segundos, fps: 8, agentes: config.agentes))
                return 0
            }
            salida(textoDemo(segundos: segundos, json: json, agentes: config.agentes))
            return 0
        case .comprobar(let explicita):
            let (config, ruta) = cargarConfiguracion(explicita: explicita, home: home)
            salida(comprobar(config: config, rutaConfig: ruta, home: home))
            return 0
        case .parar:
            return senalar(home: home, salida: salida)
        case .orden(let texto, let explicita):
            let orden = texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (leerEstandar() ?? "") : texto
            if orden.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                salida("Escribe la orden: enjambre orden \"abre Safari\"")
                return 2
            }
            let socket = RutasEnjambre.socket(home: home)
            if let respuesta = ClienteControl.enviar(ruta: socket, mensaje: .objeto(["tipo": .texto("orden"), "texto": .texto(orden), "origen": .texto("cli")]), tiempo: 900) {
                salida(respuesta["texto"]?.texto ?? respuesta.textoPlano)
                return (respuesta["ok"]?.bool ?? true) ? 0 : 1
            }
            salida("La barra de menú no está abierta: ejecuto la orden sin cursores.")
            return await ordenLocal(orden, explicita: explicita, origen: "cli", home: home, salida: salida)
        case .interfaz:
            salida("La ventana, los cursores, la voz y el ratón solo están en macOS. En esta máquina puedes probar `enjambre demo --sin-ventana` y `swift test`.")
            return 2
        }
    }

    public static func ordenLocal(_ orden: String, explicita: String?, origen: String, home: String, salida: (String) -> Void) async -> Int32 {
        let (cargada, _) = cargarConfiguracion(explicita: explicita, home: home)
        let config = cargada.aplicando(gigabytes: MemoriaEquipo.gigabytes())
        let vivos = ProcesosVivos()
        let interrupcion = Interrupcion(vivos: vivos)
        let registroURL = URL(fileURLWithPath: RutasEnjambre.registro(home: home))
        guard let registro = try? RegistroAcciones(archivo: registroURL) else {
            salida("No pude abrir el registro.")
            return 1
        }
        let neutral = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("enjambre-cerebro").path
        try? FileManager.default.createDirectory(atPath: neutral, withIntermediateDirectories: true)
        let presupuesto = config.hardware.presupuestoGB > 0 ? config.hardware.presupuestoGB : 11
        let selector = SelectorCerebros(config: config, cola: ColaModelos(presupuestoGB: presupuesto), interrupcion: interrupcion, vivos: vivos, directorioNeutral: neutral, home: home)
        selector.tokenNodo = config.nodo.token
        for nodo in config.nodos where !nodo.host.isEmpty {
            selector.nodos[nodo.nombre] = (nodo.host, nodo.puerto)
        }
        let orquestador = Orquestador(
            config: config,
            cerebro: CerebroGuion(respuestas: []),
            ejecutor: EjecutorNucleo(),
            confirmador: ConfirmadorTerminal(),
            visual: SumideroVacio(),
            interrupcion: interrupcion,
            registro: registro
        )
        orquestador.selector = selector
        orquestador.nodosVivos = {
            var vivos = Set<String>()
            for nodo in config.nodos where !nodo.host.isEmpty && ClienteNodo.eco(host: nodo.host, puerto: nodo.puerto, token: config.nodo.token) {
                vivos.insert(nodo.nombre)
            }
            return vivos
        }
        let resultado = await orquestador.ejecutar(orden: orden, origen: origen, home: home)
        salida(resultado.texto)
        return resultado.esError ? 1 : 0
    }

    private static func senalar(home: String, salida: (String) -> Void) -> Int32 {
        let socket = RutasEnjambre.socket(home: home)
        if let respuesta = ClienteControl.enviar(ruta: socket, mensaje: .objeto(["tipo": .texto("parar")]), tiempo: 3) {
            salida(respuesta["texto"]?.texto ?? "Parado.")
            return 0
        }
        let ruta = RutasEnjambre.pid(home: home)
        guard let texto = try? String(contentsOfFile: ruta, encoding: .utf8), let pid = Int32(texto.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else {
            salida("No hay un Enjambre en marcha.")
            return 1
        }
        if kill(pid, SIGUSR1) == 0 {
            salida("Señal de parada enviada.")
            return 0
        }
        salida("No pude avisar al proceso \(pid).")
        return 1
    }
}

private final class ConfirmadorTerminal: Confirmador {
    func confirmar(_ solicitud: SolicitudConfirmacion) async -> Bool {
        let terminal = isatty(fileno(stdin)) != 0
        if !terminal { return false }
        print("¿Permitir? \(solicitud.agente): \(solicitud.motivo)\n\(solicitud.detalle)\nEscribe SI para permitir: ", terminator: "")
        guard let linea = readLine() else { return false }
        return respuestaAfirmativa(linea)
    }
}

private func leerEstandar() -> String? {
    guard isatty(fileno(stdin)) == 0 else { return nil }
    let datos = FileHandle.standardInput.readDataToEndOfFile()
    let texto = String(data: datos, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return texto?.isEmpty == false ? texto : nil
}
