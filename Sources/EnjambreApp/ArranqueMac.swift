#if os(macOS)
import AppKit
import Darwin
import EnjambreNucleo

final class ArranqueMac: NSObject, NSApplicationDelegate {
    static let compartido = ArranqueMac()
    private var config = Configuracion.porDefecto()
    private let capa = CapaCursores()
    private let barra = BarraMenu()
    private let salaUI = VentanaSala()
    private let sala = Sala()
    private var voz: MotorVoz?
    private var puente: PuenteTelegram?
    private var webhook: ServidorWebhook?
    private var nodo: ServidorNodo?
    private let sonda = SondaMac()
    private var interrupcion = Interrupcion()
    private var registro: RegistroAcciones?
    private var selector: SelectorCerebros?
    private var tarea: Task<Void, Never>?
    private var generacion = 0
    private var enDemo = false
    private let operador = OperadorMac()
    private let estudio = VentanaEstudio()
    private var asistente: AsistenteMac?
    private lazy var cuentas = VentanaCuentas(home: RutasEnjambre.homeActual())

    static func principal(modo: ModoArranque) {
        let app = NSApplication.shared
        let delegado = ArranqueMac.compartido
        switch modo {
        case .demo, .interfaz(demo: true, _):
            delegado.enDemo = true
        default:
            break
        }
        app.delegate = delegado
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        config = cargar()
        let soporte = RutasEnjambre.soporte(home: RutasEnjambre.homeActual())
        try? FileManager.default.createDirectory(atPath: soporte, withIntermediateDirectories: true)
        let pidURL = URL(fileURLWithPath: RutasEnjambre.pid(home: RutasEnjambre.homeActual()))
        try? String(ProcessInfo.processInfo.processIdentifier).write(to: pidURL, atomically: true, encoding: .utf8)
        signal(SIGUSR1, SIG_IGN)
        let fuente = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        fuente.setEventHandler { [weak self] in self?.pararTodo() }
        fuente.resume()
        registro = try? RegistroAcciones(archivo: URL(fileURLWithPath: RutasEnjambre.registro(home: RutasEnjambre.homeActual())))
        prepararSelector()
        if enDemo || AsistenteMac.yaCompletado(home: RutasEnjambre.homeActual()) {
            abrirInterfaz()
        } else {
            let asistente = AsistenteMac(gigabytes: MemoriaEquipo.gigabytes())
            asistente.alTerminar = { [weak self] in self?.abrirInterfaz() }
            self.asistente = asistente
            asistente.mostrar()
        }
    }

    private func abrirInterfaz() {
        capa.iniciar()
        operador.alCursor = { [weak self] punto, nombre in
            self?.capa.fijar([CursorVisual(id: "gui", nombre: nombre, colorHex: "#FFFFFF", x: punto.x, y: punto.y, burbuja: "escribiendo", etiqueta: "app")], aviso: nil)
        }
        barra.instalar()
        cablearBarra()
        cablearSala()
        AtajosMac.compartido.alParar = { [weak self] in self?.pararTodo() }
        AtajosMac.compartido.alOrden = { [weak self] in self?.barra.mostrar() }
        AtajosMac.compartido.alVoz = { [weak self] in self?.alternarVoz() }
        AtajosMac.compartido.instalar(interfaz: config.interfaz)
        voz = MotorVoz(idioma: config.voz.idioma, enDispositivo: config.voz.reconocimientoEnDispositivo, maxCaracteres: config.voz.maxCaracteresHablados)
        voz?.alParcial = { [weak self] texto in self?.barra.fijarCampo(texto) }
        voz?.alFinal = { [weak self] texto in self?.recibirVoz(texto) }
        voz?.alError = { [weak self] texto in self?.barra.fijarResultado(texto) }
        estudio.mostrar(agentes: config.agentesVisibles())
        cuentas.alCambiar = { [weak self] in self?.refrescarEnlaces() }
        refrescarEnlaces()
        arrancarTelegram()
        arrancarWebhook()
        arrancarNodo()
        sonda.alCambiar = { [weak self] hay in
            self?.barra.fijarResultado(hay ? "Hay internet: los agentes en línea pueden unirse." : "Sin internet: se quedan los agentes locales. Los de la nube esperan.")
            self?.publicarCursoresDeEspera(enLinea: hay)
        }
        if enDemo { iniciarDemo() }
        else { publicarCursoresDeEspera(enLinea: true) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        webhook?.detener()
        nodo?.detener()
        try? FileManager.default.removeItem(atPath: RutasEnjambre.pid(home: RutasEnjambre.homeActual()))
    }

    private func cargar() -> Configuracion {
        let (cargada, _) = CLINucleo.cargarConfiguracion(explicita: nil, home: RutasEnjambre.homeActual())
        return cargada.aplicando(gigabytes: MemoriaEquipo.gigabytes())
    }

    private func prepararSelector() {
        guard let registro else { return }
        let neutral = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("enjambre-cerebro").path
        try? FileManager.default.createDirectory(atPath: neutral, withIntermediateDirectories: true)
        let cola = ColaModelos(presupuestoGB: config.hardware.presupuestoGB > 0 ? config.hardware.presupuestoGB : 11)
        let selector = SelectorCerebros(config: config, cola: cola, interrupcion: interrupcion, vivos: interrupcionProcesos(), directorioNeutral: neutral, home: RutasEnjambre.homeActual())
        selector.operador = operador
        selector.tokenNodo = config.nodo.token
        selector.identificadoresEnlazados = { [weak self] in
            self?.cuentas.enlaces().filter { $0.value }.map(\.key).reduce(into: Set<String>()) { $0.insert($1) } ?? []
        }
        for nodo in config.nodos where !nodo.host.isEmpty {
            selector.nodos[nodo.nombre] = (nodo.host, nodo.puerto)
        }
        self.selector = selector
        _ = registro
    }

    private func interrupcionProcesos() -> ProcesosVivos { .compartido }

    private func cablearBarra() {
        barra.alEjecutar = { [weak self] texto in self?.lanzar(texto, origen: "menu") }
        barra.alHablar = { [weak self] in self?.alternarVoz() }
        barra.alDemo = { [weak self] in self?.iniciarDemo() }
        barra.alParar = { [weak self] in self?.pararTodo() }
        barra.alSala = { [weak self] in self?.salaUI.mostrar() }
        barra.alCuentas = { [weak self] in
            self?.cuentas.alCambiar = { [weak self] in self?.refrescarEnlaces() }
            self?.cuentas.mostrar()
        }
        barra.alPermisos = {
            _ = PermisosMac.accesibilidad(pedir: true)
            _ = PermisosMac.grabacion(pedir: true)
            PermisosMac.abrirAjustes("Accessibility")
            self.barra.fijarResultado(PermisosMac.resumen())
        }
        barra.alRegistro = { [weak self] in
            self?.barra.fijarResultado(self?.registro?.textoReciente(40) ?? "Sin registro.")
        }
    }

    private func cablearSala() {
        salaUI.alEnviar = { [weak self] texto in self?.aporteUsuario(texto) }
        salaUI.alAprobar = { [weak self] in Task { await self?.sala.resolver(.aprobar) } }
        salaUI.alVetar = { [weak self] in Task { await self?.sala.resolver(.vetar) } }
        Task {
            await sala.alPublicar = { [weak self] mensaje in
                self?.salaUI.agregar(mensaje)
                self?.espejar(mensaje)
                if mensaje.origen == .agente {
                    self?.capa.fijar([CursorVisual(id: mensaje.autor, nombre: mensaje.autor, colorHex: "#E8F27A", x: 0.5, y: 0.4, burbuja: String(mensaje.texto.prefix(80)), etiqueta: "chat")], aviso: nil)
                }
            }
        }
    }

    private func aporteUsuario(_ texto: String) {
        Task {
            let pendiente = await sala.hayDecisionPendiente()
            switch MesaDebate.interpretarAporte(texto, decisionPendiente: pendiente) {
            case .aprobar:
                await sala.resolver(.aprobar)
            case .vetar:
                await sala.resolver(.vetar)
                pararTodo()
            case .mensaje:
                let menciones = MesaDebate.menciones(en: texto, agentes: config.agentesVisibles())
                _ = await sala.publicar(autor: "Tú", origen: .usuario, texto: texto, menciones: menciones)
                if !pendiente { lanzar(texto, origen: "chat") }
            }
        }
    }

    private func recibirVoz(_ texto: String) {
        barra.fijarCampo(texto)
        aporteUsuario(texto)
    }

    private func alternarVoz() {
        voz?.pedirPermisos { [weak self] ok in
            guard ok else { return }
            self?.voz?.alternar()
        }
    }

    func lanzar(_ orden: String, origen: String) {
        let texto = orden.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else { return }
        enDemo = false
        generacion += 1
        let generacionActual = generacion
        let anterior = interrupcion
        interrupcion = Interrupcion()
        selector?.interrupcion = interrupcion
        tarea?.cancel()
        barra.marcarOcupado(true)
        barra.mostrar()
        salaUI.mostrar()
        tarea = Task { [weak self] in
            await anterior.parar()
            guard let self, generacionActual == self.generacion else { return }
            guard let registro = self.registro, let selector = self.selector else { return }
            let orquestador = Orquestador(
                config: self.config,
                cerebro: CerebroGuion(respuestas: []),
                ejecutor: EjecutorNucleo(extra: self.herramientas()),
                confirmador: ConfirmadorMac(),
                visual: PuenteVisual(capa: self.capa, barra: self.barra, hablar: { [weak self] frase in
                    guard self?.config.voz.sintetizarRespuestas == true else { return }
                    self?.voz?.hablar(frase)
                }),
                interrupcion: self.interrupcion,
                registro: registro,
                descripcionPantalla: self.descripcionPantalla()
            )
            orquestador.selector = selector
            orquestador.sala = self.sala
            orquestador.sonda = self.sonda
            orquestador.identificadoresEnlazados = { [weak self] in
                self?.cuentas.enlaces().compactMap { $0.value ? $0.key : nil }.reduce(into: Set<String>()) { $0.insert($1) } ?? []
            }
            orquestador.nodosVivos = { [weak self] in
                guard let self else { return [] }
                var vivos = Set<String>()
                for nodo in self.config.nodos where ClienteNodo.eco(host: nodo.host, puerto: nodo.puerto, token: self.config.nodo.token) {
                    vivos.insert(nodo.nombre)
                }
                return vivos
            }
            let resultado = await orquestador.ejecutar(orden: texto, origen: origen, home: RutasEnjambre.homeActual())
            await MainActor.run {
                self.barra.fijarResultado(resultado.texto)
                self.barra.marcarOcupado(false)
            }
            _ = await self.sala.publicar(autor: "Enjambre", origen: .sistema, texto: resultado.texto)
        }
    }

    func pararTodo() {
        generacion += 1
        let actual = interrupcion
        Task { await actual.parar() }
        ProcesosVivos.compartido.matarTodos()
        tarea?.cancel()
        enDemo = false
        capa.fijar([], aviso: "Parado")
        barra.marcarOcupado(false)
        barra.fijarResultado("Parado. Los agentes se detuvieron.")
        Task { _ = await sala.publicar(autor: "Enjambre", origen: .sistema, texto: "Parado.") }
    }

    private func refrescarEnlaces() {
        estudio.aplicarEnlaces(cuentas.enlaces())
    }

    func actualizarEstudio(_ estados: [EstadoAgente], aviso: String) {
        estudio.aplicarEstados(estados, aviso: aviso)
    }

    private func iniciarDemo() {
        enDemo = true
        let agentes = config.agentesVisibles()
        salaUI.mostrar()
        estudio.reproducirDemo(agentes: agentes)
        capa.reproducirDemo(agentes: agentes) { [weak self] autor, texto in
            Task { _ = await self?.sala.publicar(autor: autor, origen: .agente, texto: texto) }
        }
    }

    private func publicarCursoresDeEspera(enLinea: Bool) {
        let cursores = config.agentesVisibles().map { agente in
            let dormido = (agente.modalidad == .online || (agente.modalidad == .gui && agente.requiereRed)) && !enLinea
            return CursorVisual(
                id: agente.id,
                nombre: agente.nombre,
                colorHex: agente.color,
                x: agente.anclaX,
                y: agente.anclaY,
                burbuja: dormido ? "sin red" : nil,
                opacidad: dormido ? 0.35 : 0.7,
                etiqueta: dormido ? "sin red" : (agente.modalidad == .local ? "local" : (agente.modalidad == .gui ? "app" : "en línea")),
                dormido: dormido
            )
        }
        if config.interfaz.cursoresEnReposo || enDemo {
            capa.fijar(cursores, aviso: nil)
        }
    }

    private func herramientas() -> HerramientasMac {
        let herramientas = HerramientasMac(operador: operador)
        herramientas.adaptadores = config.adaptadores
        return herramientas
    }

    private func descripcionPantalla() -> String {
        let pantalla = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        let ancho = Int(pantalla?.frame.width ?? 0)
        let alto = Int(pantalla?.frame.height ?? 0)
        return "\(ancho)×\(alto) puntos, origen arriba a la izquierda"
    }

    private func arrancarTelegram() {
        guard config.telegram.activo, !config.telegram.token.isEmpty else { return }
        let puente = PuenteTelegram(token: config.telegram.token, chatsPermitidos: Set(config.telegram.chatIDs), tiempoConfirmacion: config.seguridad.tiempoConfirmacionSegundos)
        puente.chatGrupo = config.telegram.chatGrupo
        puente.registro = registro
        puente.alOrden = { [weak self] texto, _ in
            guard let self else { return "" }
            return await withCheckedContinuation { continuacion in
                DispatchQueue.main.async {
                    self.lanzar(texto, origen: "telegram")
                    continuacion.resume(returning: "Orden recibida. Mira el Mac.")
                }
            }
        }
        puente.alParar = { [weak self] in self?.pararTodo() }
        puente.alDemo = { [weak self] in self?.iniciarDemo() }
        puente.alEstado = { [weak self] in self?.barraTextoEstado() ?? "" }
        puente.alSugerencia = { [weak self] autor, texto in
            Task { _ = await self?.sala.publicar(autor: autor, origen: .telegram, texto: texto) }
        }
        puente.iniciar()
        self.puente = puente
    }

    private func espejar(_ mensaje: MensajeSala) {
        guard mensaje.origen != .telegram, config.telegram.chatGrupo != 0, let puente else { return }
        let prefijo = mensaje.sugerencia ? "[sugerencia] " : ""
        Task { await puente.enviar(chatID: self.config.telegram.chatGrupo, texto: "\(prefijo)\(mensaje.autor): \(mensaje.texto)") }
    }

    private func arrancarWebhook() {
        guard config.webhook.activo, !config.webhook.secreto.isEmpty else { return }
        let servidor = ServidorWebhook(secreto: config.webhook.secreto)
        servidor.mensajes = { [weak self] in
            guard let self else { return [] }
            return awaitBlocking { await self.sala.recientes() }
        }
        servidor.alSugerencia = { [weak self] autor, texto in
            Task { _ = await self?.sala.publicar(autor: autor, origen: .webhook, texto: texto) }
        }
        try? servidor.iniciar(puerto: config.webhook.puerto, exponerLAN: config.webhook.exponerLAN)
        webhook = servidor
    }

    private func arrancarNodo() {
        guard config.nodo.rol == "trabajador", !config.nodo.token.isEmpty else { return }
        let servidor = ServidorNodo(token: config.nodo.token)
        servidor.alCompletar = { [weak self] modelo, sistema, usuario in
            guard let self, let selector = self.selector else { return "Nodo sin modelo." }
            let falso = AgenteConfig(id: "nodo", nombre: "Nodo", color: "#FFFFFF", rol: "", herramientas: [], anclaX: 0.5, anclaY: 0.5, modalidad: .local, proveedor: .ollama, modelo: modelo, memoriaGB: 4)
            return awaitBlocking {
                (try? await selector.completar(agente: falso, sistema: sistema, usuario: usuario, enLinea: false, nodosVivos: [])) ?? "El modelo local no respondió."
            }
        }
        try? servidor.iniciar(puerto: config.nodo.puerto)
        nodo = servidor
    }

    private func barraTextoEstado() -> String {
        let preset = config.hardware.preset
        return "Preset \(preset). Debate \(config.debate.activo ? "activo" : "apagado")."
    }
}

private func awaitBlocking<T>(_ cuerpo: @escaping () async -> T) -> T {
    let semaforo = DispatchSemaphore(value: 0)
    let caja = CajaValor<T>()
    Task {
        caja.valor = await cuerpo()
        semaforo.signal()
    }
    semaforo.wait()
    return caja.valor!
}

private final class CajaValor<T>: @unchecked Sendable {
    var valor: T?
}

final class HerramientasMac: HerramientaExtra {
    let operador: OperadorMac
    var adaptadores: [AdaptadorChat] = AdaptadorChat.integrados
    init(operador: OperadorMac) { self.operador = operador }
    var nombres: [String] { ["osascript", "abrir", "raton", "teclado", "captura", "ui_arbol", "operar_chat"] }

    func ejecutar(_ llamada: LlamadaHerramienta, contexto: ContextoEjecucion) async -> ResultadoHerramienta {
        switch llamada.nombre {
        case "operar_chat":
            let id = llamada.texto("adaptador") ?? "antigravity"
            let texto = llamada.texto("texto") ?? llamada.texto("prompt") ?? ""
            if let bloqueo = await exigirRiesgo(Seguridad.evaluarTeclado(texto), detalle: texto, contexto: contexto, herramienta: "operar_chat") {
                return bloqueo
            }
            guard let adaptador = adaptadores.first(where: { $0.id == id }) ?? AdaptadorChat.integrados.first(where: { $0.id == id }) else {
                return ResultadoHerramienta(salida: "No hay un adaptador llamado \(id).", esError: true)
            }
            let salida = await operador.preguntar(adaptador: adaptador, texto: texto) { _ in }
            return ResultadoHerramienta(salida: salida, esError: salida.hasPrefix("No ") || salida.hasPrefix("Falta"), burbuja: adaptador.nombre)
        case "abrir":
            let destino = llamada.texto("destino") ?? ""
            if let bloqueo = await exigirRiesgo(Seguridad.evaluarAbrir(destino), detalle: destino, contexto: contexto, herramienta: "abrir") {
                return bloqueo
            }
            if destino.hasPrefix("http"), let url = URL(string: destino) {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/\(destino).app"), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
            return ResultadoHerramienta(salida: "Abrí \(destino).")
        case "osascript":
            let fuente = llamada.texto("fuente") ?? ""
            if let bloqueo = await exigirRiesgo(Seguridad.evaluarAppleScript(fuente), detalle: fuente, contexto: contexto, herramienta: "osascript") {
                return bloqueo
            }
            let resultado = LanzadorProceso.ejecutar(ejecutable: "/usr/bin/osascript", argumentos: ["-e", fuente], tiempoLimite: 30, vivos: contexto.vivos)
            return ResultadoHerramienta(salida: resultado.salida + resultado.error, esError: resultado.codigo != 0)
        case "captura":
            guard PermisosMac.grabacion(pedir: true) else {
                return ResultadoHerramienta(salida: "Falta el permiso de grabación de pantalla.", esError: true)
            }
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("enjambre-captura.jpg")
            _ = LanzadorProceso.ejecutar(ejecutable: "/usr/sbin/screencapture", argumentos: ["-x", "-t", "jpg", url.path], tiempoLimite: 10, vivos: contexto.vivos)
            return ResultadoHerramienta(salida: "Captura guardada en \(url.path).")
        case "ui_arbol":
            guard PermisosMac.accesibilidad(pedir: true) else {
                return ResultadoHerramienta(salida: "Falta Accesibilidad para leer la interfaz.", esError: true)
            }
            return ResultadoHerramienta(salida: "Árbol de accesibilidad disponible para el operador de apps.")
        case "raton":
            let accion = llamada.texto("accion") ?? "mover"
            if let bloqueo = await exigirRiesgo(Seguridad.evaluarRaton(accion: accion), detalle: accion, contexto: contexto, herramienta: "raton") {
                return bloqueo
            }
            let salida = await operador.moverRaton(x: llamada.numero("x") ?? 0.5, y: llamada.numero("y") ?? 0.5, normalizado: llamada.bool("normalizado") ?? true, accion: accion)
            return ResultadoHerramienta(salida: salida, burbuja: "ratón")
        case "teclado":
            let texto = llamada.texto("texto") ?? llamada.texto("atajo") ?? ""
            if let bloqueo = await exigirRiesgo(Seguridad.evaluarTeclado(texto), detalle: texto, contexto: contexto, herramienta: "teclado") {
                return bloqueo
            }
            if let atajo = llamada.texto("atajo") {
                return ResultadoHerramienta(salida: "Atajo \(atajo) anotado. Para pulsarlo usa operar_chat o un atajo simple.", burbuja: "teclado")
            }
            let salida = await operador.escribirTeclado(texto)
            return ResultadoHerramienta(salida: salida, burbuja: "teclado")
        default:
            return ResultadoHerramienta(salida: "Herramienta no disponible.", esError: true)
        }
    }
}

final class PuenteVisual: SumideroVisual {
    let capa: CapaCursores
    let barra: BarraMenu
    let hablar: (String) -> Void
    init(capa: CapaCursores, barra: BarraMenu, hablar: @escaping (String) -> Void) {
        self.capa = capa
        self.barra = barra
        self.hablar = hablar
    }
    func actualizar(_ cursores: [CursorVisual]) async {
        let copia = cursores
        await MainActor.run { self.capa.fijar(copia, aviso: nil) }
    }
    func celebrar() async {
        await MainActor.run { self.capa.celebrar(agentes: []) }
        try? await Task.sleep(nanoseconds: 1_600_000_000)
    }
    func decir(_ texto: String) async {
        let copia = texto
        await MainActor.run {
            self.barra.fijarResultado(copia)
            self.hablar(copia)
        }
    }
    func estadoAgentes(_ estados: [EstadoAgente]) async {
        let texto = estados.map { "\($0.nombre): \($0.detalle.isEmpty ? $0.estado : $0.detalle)" }.joined(separator: "\n")
        await MainActor.run {
            self.barra.fijarEstados(texto)
            ArranqueMac.compartido.actualizarEstudio(estados, aviso: "En curso")
        }
    }
}
#endif
