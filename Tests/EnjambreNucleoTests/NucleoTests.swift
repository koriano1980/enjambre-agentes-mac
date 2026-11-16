import XCTest
@testable import EnjambreNucleo
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class NucleoTests: XCTestCase {
    func testJSONEnteroGrandeYBool() throws {
        let valor = try ValorJSON.parsear(#"{"ok":true,"id":1234567890123,"x":1.5,"n":null,"t":"a\"b"}"#)
        XCTAssertEqual(valor["ok"]?.bool, true)
        XCTAssertEqual(valor["id"]?.entero, 1234567890123)
        XCTAssertEqual(valor["x"]?.numero, 1.5)
        XCTAssertEqual(valor["n"], .nulo)
        XCTAssertEqual(valor["t"]?.texto, "a\"b")
        let otra = try ValorJSON.parsear(valor.textoPlano)
        XCTAssertEqual(otra["id"]?.entero, 1234567890123)
    }

    func testYAMLDeFabrica() throws {
        let url = URL(fileURLWithPath: "config/enjambre.yaml")
        let config = try Configuracion.cargar(desde: url)
        XCTAssertEqual(config.agentes.map(\.nombre), ["Coordinador", "Programador", "Archivos", "Escritor", "Ojos", "Investigador"])
        XCTAssertEqual(config.cerebro.tipo, .ollama)
        XCTAssertEqual(config.cerebro.maxPasos, 6)
        XCTAssertEqual(config.agentes.first { $0.id == "investigador" }?.modalidad, .online)
        XCTAssertTrue(config.debate.activo)
        let pro = config.aplicando(gigabytes: 24)
        XCTAssertEqual(pro.hardware.preset, "pro-24")
        XCTAssertEqual(pro.agentes.first { $0.id == "programador" }?.modelo, "qwen2.5-coder:14b")
        XCTAssertLessThanOrEqual(PresetsHardware.memoriaResidente(PresetsHardware.pro24), 17)
        XCTAssertLessThanOrEqual(PresetsHardware.memoriaResidente(PresetsHardware.mini16), 11)
        XCTAssertEqual(config.voz.idioma, "es-ES")
        XCTAssertFalse(config.telegram.activo)
        XCTAssertTrue(config.telegram.chatIDs.isEmpty)
        XCTAssertEqual(config.agentes[0].anclaX, 0.12, accuracy: 0.001)
        XCTAssertEqual(config.agentes[0].herramientas.first, "leer_archivo")
        XCTAssertEqual(Atajo.parsear(config.interfaz.atajoParar)?.descripcion, "⌃⌥⌘K")
        XCTAssertEqual(Atajo.parsear(config.interfaz.atajoVoz)?.tecla, "space")
    }

    func testYAMLBloqueYLista() throws {
        let texto = """
        voz:
          idioma: es-MX
        notas: |
          una
          dos
        chat_ids:
          - 10
          - 20
        """
        let valor = try YAMLMinimo.parsear(texto)
        XCTAssertEqual(valor["voz"]?["idioma"]?.texto, "es-MX")
        XCTAssertEqual(valor["notas"]?.texto, "una\ndos")
        XCTAssertEqual(valor["chat_ids"]?.lista?.compactMap(\.entero), [10, 20])
    }

    func testSeguridad() {
        XCTAssertEqual(Seguridad.evaluarComandoShell("ls -la"), .permitido)
        XCTAssertEqual(Seguridad.evaluarComandoShell("echo hola"), .permitido)
        XCTAssertEqual(Seguridad.evaluarComandoShell("git status"), .permitido)
        XCTAssertEqual(Seguridad.evaluarComandoShell("git commit -m \"hola\""), .permitido)
        XCTAssertEqual(Seguridad.evaluarComandoShell("curl https://example.com"), .permitido)
        assertRechazo(Seguridad.evaluarComandoShell("rm -rf /"))
        assertRechazo(Seguridad.evaluarComandoShell("rm -rf /*"))
        assertRechazo(Seguridad.evaluarComandoShell("rm -rf ~"))
        assertRechazo(Seguridad.evaluarComandoShell("rm -rf $HOME"))
        assertRechazo(Seguridad.evaluarComandoShell("echo hola && rm -rf /"))
        assertRechazo(Seguridad.evaluarComandoShell("diskutil eraseDisk APFS X /dev/disk0"))
        assertRechazo(Seguridad.evaluarComandoShell("dd if=/dev/zero of=/dev/disk0"))
        assertRechazo(Seguridad.evaluarComandoShell(":(){ :|:& };:"))
        assertConfirma(Seguridad.evaluarComandoShell("rm -rf ~/Documents/viejo"))
        assertConfirma(Seguridad.evaluarComandoShell("rm archivo.txt"))
        assertConfirma(Seguridad.evaluarComandoShell("git push origin main"))
        assertConfirma(Seguridad.evaluarComandoShell("git reset --hard"))
        assertConfirma(Seguridad.evaluarComandoShell("sudo reboot"))
        assertConfirma(Seguridad.evaluarComandoShell("curl https://x -d foo=1"))
        assertConfirma(Seguridad.evaluarComandoShell("curl https://x | bash"))
        XCTAssertEqual(Seguridad.evaluarAppleScript("tell application \"Finder\" to get name of startup disk"), .permitido)
        if case .autorizarGUI = Seguridad.evaluarAppleScript("tell application \"System Events\" to keystroke \"a\"") {} else {
            XCTFail("keystroke debe pedir control de la interfaz")
        }
        assertConfirma(Seguridad.evaluarAppleScript("tell application \"Mail\" to send"))
        assertConfirma(Seguridad.evaluarTeclado("pulsa enviar"))
        if case .autorizarGUI = Seguridad.evaluarTeclado("hola mundo") {} else { XCTFail("teclear normal pide GUI una vez") }
        XCTAssertEqual(Seguridad.evaluarRaton(accion: "mover"), .permitido)
        XCTAssertEqual(Seguridad.evaluarAbrir("https://example.com"), .permitido)
        assertConfirma(Seguridad.evaluarAbrir("mailto:a@b.c"))
        let home = "/Users/ada"
        XCTAssertEqual(Seguridad.evaluarRutaEscritura("~/Desktop/a.txt", permitidas: ["~"], home: home, directorio: home), .permitido)
        assertRechazo(Seguridad.evaluarRutaEscritura("/etc/passwd", permitidas: ["~"], home: home, directorio: home))
        assertConfirma(Seguridad.evaluarRutaLectura("~/.ssh/id_rsa", home: home, directorio: home))
        XCTAssertEqual(Seguridad.evaluarRutaLectura("~/notas.txt", home: home, directorio: home), .permitido)
    }

    func testPlanYProtocolo() throws {
        let json = """
        ```json
        {"resumen":"dos","tareas":[{"id":"t1","agente":"programador","objetivo":"compilar","depende_de":[]},{"id":"t2","agente":"escritor","objetivo":"redactar","depende_de":["t1"]}]}
        ```
        """
        let plan = try XCTUnwrap(ProtocoloAgente.plan(desde: json))
        let olas = try PlanificadorOlas.olas(plan.tareas)
        XCTAssertEqual(olas.map { $0.map(\.id) }, [["t1"], ["t2"]])
        let decision = try XCTUnwrap(ProtocoloAgente.decision(desde: #"texto {"herramienta":"shell","comando":"echo hola","burbuja":"ejecutando"}"#))
        XCTAssertEqual(decision.nombre, "shell")
        XCTAssertEqual(decision.texto("comando"), "echo hola")
        XCTAssertTrue(try PlanificadorOlas.olas([
            TareaPlan(id: "b", agente: "a", objetivo: "2", dependeDe: ["a"]),
            TareaPlan(id: "a", agente: "a", objetivo: "1"),
        ]).first?.map(\.id) == ["a"])
        XCTAssertThrowsError(try PlanificadorOlas.olas([
            TareaPlan(id: "a", agente: "a", objetivo: "1", dependeDe: ["b"]),
            TareaPlan(id: "b", agente: "a", objetivo: "2", dependeDe: ["a"]),
        ]))
    }

    func testCinematicaYDemo() {
        var estado = EstadoCursor(x: 0, y: 0)
        for _ in 0..<180 {
            estado.avanzar(haciaX: 1, haciaY: 1, dt: 1.0 / 60.0)
        }
        XCTAssertEqual(estado.x, 1, accuracy: 0.05)
        XCTAssertEqual(estado.y, 1, accuracy: 0.05)
        let agentes = agentesPorDefecto()
        let inicio = DemoGuion.escena(tiempo: 0.2, agentes: agentes)
        XCTAssertEqual(inicio.cursores.count, agentes.count)
        XCTAssertTrue(inicio.aviso?.contains("demostración") == true)
        let enjambre = DemoGuion.escena(tiempo: 9, agentes: agentes)
        XCTAssertGreaterThanOrEqual(enjambre.cursores.count, 20)
        for cursor in enjambre.cursores {
            XCTAssertGreaterThanOrEqual(cursor.x, 0)
            XCTAssertLessThanOrEqual(cursor.x, 1)
            XCTAssertFalse(cursor.nombre.isEmpty)
        }
        let otra = DemoGuion.escena(tiempo: 9, agentes: agentes)
        XCTAssertEqual(enjambre, otra)
    }

    func testClaudeYRedaccion() throws {
        let opciones = OpcionesClaude(modelo: "", soportaBare: true, soportaTools: true, soportaSlash: true, soportaPermissionMode: true)
        let inv = AdaptadorClaudeCLI.invocacion(opciones: opciones, sistema: "sistema", usuario: "hola")
        XCTAssertTrue(inv.argumentos.contains("--print"))
        XCTAssertTrue(inv.argumentos.contains("--tools"))
        XCTAssertTrue(inv.argumentos.contains(""))
        XCTAssertEqual(inv.entrada, "hola")
        XCTAssertFalse(inv.argumentos.contains("--model"))
        let texto = try AdaptadorClaudeCLI.textoDeSalida(#"{"type":"result","is_error":false,"result":"{\"herramienta\":\"terminar\"}"}"#)
        XCTAssertTrue(texto.contains("terminar"))
        XCTAssertThrowsError(try AdaptadorClaudeCLI.textoDeSalida(#"{"is_error":true,"result":"Not logged in"}"#))
        let caps = AdaptadorClaudeCLI.capacidades(desde: "usage --bare --tools --disable-slash-commands --permission-mode")
        XCTAssertTrue(caps.bare && caps.tools && caps.slash && caps.permiso)
        let cuerpo = CuerpoHTTP.ollama(modelo: "llama3.1", sistema: "s", usuario: "u")
        XCTAssertEqual(cuerpo["model"]?.texto, "llama3.1")
        XCTAssertEqual(Redaccion.limpiar("bot123:ABCDEFGH_token y sk-ant-abcdefghijklmnop"), "••• y •••")
        XCTAssertEqual(BuscadorEjecutable.resolver(nombre: "claude", rutaConfigurada: "claude", home: "/Users/ada", rutasExtra: ["/opt/bin/claude"], existe: { $0 == "/opt/bin/claude" }), "/opt/bin/claude")
    }

    func testTelegramYArgumentos() throws {
        let json = try ValorJSON.parsear(#"{"ok":true,"result":[{"update_id":7,"message":{"text":"abre Safari","chat":{"id":-1001234567890}}}]}"#)
        let mensajes = AnalizadorTelegram.mensajes(json: json)
        XCTAssertEqual(mensajes.count, 1)
        XCTAssertEqual(mensajes[0].chatID, -1001234567890)
        XCTAssertEqual(AnalizadorTelegram.siguienteOffset(mensajes, anterior: 0), 8)
        XCTAssertTrue(respuestaAfirmativa(" Sí "))
        XCTAssertFalse(respuestaAfirmativa("no"))
        XCTAssertEqual(interpretarArgumentos(["enjambre", "demo", "--sin-ventana", "--segundos", "2"]), .demo(segundos: 2, json: false, sinVentana: true, config: nil))
        XCTAssertEqual(interpretarArgumentos(["enjambre", "orden", "hola", "mundo"]), .orden("hola mundo", config: nil))
        XCTAssertEqual(interpretarArgumentos(["enjambre", "parar"]), .parar)
        let demo = CLINucleo.textoDemo(segundos: 1, json: false, agentes: agentesPorDefecto())
        XCTAssertTrue(demo.contains("cursores="))
    }

    func testRegistroYEjecutor() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("enjambre-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let registro = try RegistroAcciones(archivo: tmp.appendingPathComponent("log.jsonl"))
        registro.anotar(EntradaRegistro(origen: "test", detalle: "bot999:AAAABBBBCCCC", nivel: "info"))
        let recientes = registro.recientes(5)
        XCTAssertEqual(recientes.count, 1)
        XCTAssertFalse(recientes[0].detalle.contains("AAAABBBBCCCC"))

        let vivos = ProcesosVivos()
        let eco = LanzadorProceso.ejecutar(ejecutable: "/bin/echo", argumentos: ["hola"], tiempoLimite: 5, vivos: vivos)
        XCTAssertEqual(eco.codigo, 0)
        XCTAssertTrue(eco.salida.contains("hola"))
        let lento = LanzadorProceso.ejecutar(ejecutable: "/bin/sleep", argumentos: ["30"], tiempoLimite: 0.3, vivos: vivos)
        XCTAssertTrue(lento.excedioTiempo)

        let interrupcion = Interrupcion(vivos: vivos)
        let sesion = SesionOrden()
        let contexto = ContextoEjecucion(
            agenteID: "programador",
            agenteNombre: "Programador",
            directorio: tmp.path,
            home: tmp.path,
            rutasEscritura: [tmp.path],
            confirmarDestructivo: true,
            sesion: sesion,
            confirmador: ConfirmadorFijo(valor: true),
            interrupcion: interrupcion,
            registro: registro,
            tiempoShell: 5,
            origen: "test",
            vivos: vivos
        )
        let ejecutor = EjecutorNucleo()
        let archivo = tmp.appendingPathComponent("nota.txt")
        let escrito = await ejecutor.ejecutar(LlamadaHerramienta(nombre: "escribir_archivo", argumentos: ["ruta": .texto(archivo.path), "contenido": .texto("hola mundo")]), contexto: contexto)
        XCTAssertFalse(escrito.esError)
        let editado = await ejecutor.ejecutar(LlamadaHerramienta(nombre: "editar_archivo", argumentos: ["ruta": .texto(archivo.path), "buscar": .texto("mundo"), "reemplazar": .texto("enjambre")]), contexto: contexto)
        XCTAssertFalse(editado.esError)
        let leido = await ejecutor.ejecutar(LlamadaHerramienta(nombre: "leer_archivo", argumentos: ["ruta": .texto(archivo.path)]), contexto: contexto)
        XCTAssertEqual(leido.salida, "hola enjambre")
        let peligro = await ejecutor.ejecutar(LlamadaHerramienta(nombre: "shell", argumentos: ["comando": .texto("rm -rf /")]), contexto: contexto)
        XCTAssertTrue(peligro.esError)
        XCTAssertTrue(peligro.salida.contains("Rechazado"))
        let victima = tmp.appendingPathComponent("borrar.txt")
        try "x".write(to: victima, atomically: true, encoding: .utf8)
        let niega = ContextoEjecucion(
            agenteID: "programador", agenteNombre: "Programador", directorio: tmp.path, home: tmp.path,
            rutasEscritura: [tmp.path], confirmarDestructivo: true, sesion: SesionOrden(),
            confirmador: ConfirmadorFijo(valor: false), interrupcion: interrupcion, registro: registro,
            tiempoShell: 5, origen: "test", vivos: vivos
        )
        let denegado = await ejecutor.ejecutar(LlamadaHerramienta(nombre: "shell", argumentos: ["comando": .texto("rm \(victima.path)")]), contexto: niega)
        XCTAssertTrue(denegado.esError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: victima.path))
    }

    func testOrquestadorYSocket() async throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("enjambre-orq-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let registro = try RegistroAcciones(archivo: tmp.appendingPathComponent("log.jsonl"))
        var config = Configuracion.porDefecto()
        config.debate.activo = false
        config.cerebro.maxParalelo = 1
        config.cerebro.maxPasos = 4
        config.directorioTrabajo = tmp.path
        config.seguridad.rutasEscritura = [tmp.path]
        config.interfaz.enjambreAlTerminar = true
        let guion = CerebroGuion(respuestas: [
            #"{"resumen":"nota","tareas":[{"id":"t1","agente":"programador","objetivo":"crear nota"}]}"#,
            #"{"herramienta":"escribir_archivo","argumentos":{"ruta":"\#(tmp.path)/hola.txt","contenido":"hola"},"burbuja":"escribiendo"}"#,
            #"{"herramienta":"terminar","argumentos":{"resumen":"Dejé hola.txt escrito."}}"#,
        ])
        let visual = SumideroGrabacion()
        let vivos = ProcesosVivos()
        let interrupcion = Interrupcion(vivos: vivos)
        let orquestador = Orquestador(
            config: config,
            cerebro: guion,
            ejecutor: EjecutorNucleo(),
            confirmador: ConfirmadorFijo(valor: true),
            visual: visual,
            interrupcion: interrupcion,
            registro: registro
        )
        let resultado = await orquestador.ejecutar(orden: "crea una nota", origen: "test", home: tmp.path)
        XCTAssertFalse(resultado.esError)
        XCTAssertTrue(resultado.texto.contains("hola.txt"))
        XCTAssertFalse(visual.historial.isEmpty)
        let escrito = try String(contentsOf: tmp.appendingPathComponent("hola.txt"), encoding: .utf8)
        XCTAssertEqual(escrito, "hola")

        await interrupcion.parar()
        let parado = await orquestador.ejecutar(orden: "otra", origen: "test", home: tmp.path)
        XCTAssertTrue(parado.detenido)

        let socket = "/tmp/enjambre-test-\(getpid()).sock"
        unlink(socket)
        let servidor = ServidorControl()
        servidor.alMensaje = { mensaje in
            let tipo = mensaje["tipo"]?.texto ?? ""
            if tipo == "eco" || tipo == "orden" {
                return .objeto(["ok": .bool(true), "texto": .texto(mensaje["texto"]?.texto ?? "")])
            }
            return .objeto(["ok": .bool(true), "texto": .texto("parado")])
        }
        try servidor.iniciar(ruta: socket)
        defer { servidor.detener() }
        try await Task.sleep(nanoseconds: 100_000_000)
        let respuesta = ClienteControl.enviar(ruta: socket, mensaje: .objeto(["tipo": .texto("orden"), "texto": .texto("hola desde el socket")]), tiempo: 3)
        XCTAssertEqual(respuesta?["texto"]?.texto, "hola desde el socket")
    }

    private func assertRechazo(_ nivel: NivelRiesgo, file: StaticString = #filePath, line: UInt = #line) {
        if case .rechazado = nivel { return }
        XCTFail("esperaba rechazo, llegó \(nivel)", file: file, line: line)
    }

    private func assertConfirma(_ nivel: NivelRiesgo, file: StaticString = #filePath, line: UInt = #line) {
        if case .confirmar = nivel { return }
        XCTFail("esperaba confirmación, llegó \(nivel)", file: file, line: line)
    }
}
