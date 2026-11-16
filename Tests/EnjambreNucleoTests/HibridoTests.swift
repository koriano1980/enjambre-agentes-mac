import XCTest
@testable import EnjambreNucleo

final class HibridoTests: XCTestCase {
    func testSHA256YFirma() {
        XCTAssertEqual(Cripto.firma(secreto: "", mensaje: "").isEmpty, false)
        XCTAssertEqual(
            Cripto.hex(Cripto.sha256([])),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        XCTAssertEqual(
            Cripto.firma(secreto: "key", mensaje: "The quick brown fox jumps over the lazy dog"),
            "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8"
        )
        XCTAssertTrue(Cripto.firmaValida(secreto: "key", mensaje: "abc", firmaHex: Cripto.firma(secreto: "key", mensaje: "abc")))
        XCTAssertFalse(Cripto.firmaValida(secreto: "key", mensaje: "abc", firmaHex: "00"))
    }

    func testPresetsYRutas() {
        XCTAssertEqual(PresetsHardware.elegir(gigabytes: 24, forzado: "auto").id, "pro-24")
        XCTAssertEqual(PresetsHardware.elegir(gigabytes: 16, forzado: "auto").id, "mini-16")
        XCTAssertEqual(PresetsHardware.elegir(gigabytes: 64, forzado: "mini-16").id, "mini-16")
        XCTAssertLessThanOrEqual(PresetsHardware.memoriaResidente(PresetsHardware.pro24), PresetsHardware.pro24.presupuestoGB)
        XCTAssertLessThanOrEqual(PresetsHardware.memoriaResidente(PresetsHardware.mini16), PresetsHardware.mini16.presupuestoGB)
        let mini = Configuracion.porDefecto().aplicando(gigabytes: 16)
        XCTAssertEqual(mini.agentes.first { $0.id == "coordinador" }?.modelo, mini.agentes.first { $0.id == "programador" }?.modelo)
        XCTAssertEqual(mini.agentes.first { $0.id == "ojos" }?.modelo, "moondream")
        let investigador = agentesPorDefecto().first { $0.id == "investigador" }!
        if case .dormido = MesaDebate.ruta(de: investigador, enLinea: false, nodosVivos: []) {} else {
            XCTFail("el investigador debe dormirse sin red")
        }
        if case .nube = MesaDebate.ruta(de: investigador, enLinea: true, nodosVivos: []) {} else {
            XCTFail("con red el investigador entra")
        }
        let activos = MesaDebate.activos(agentesPorDefecto(), enLinea: false, nodosVivos: [])
        XCTAssertFalse(activos.contains { $0.id == "investigador" })
        let reasignada = MesaDebate.reasignar(TareaPlan(id: "t", agente: "investigador", objetivo: "buscar"), activos: activos)
        XCTAssertNotEqual(reasignada.agente, "investigador")
        let peligro = Plan(resumen: "", tareas: [TareaPlan(id: "t", agente: "archivos", objetivo: "hay que borrar la carpeta vieja")])
        XCTAssertTrue(MesaDebate.planRequiereAprobacion(plan: peligro, politica: .siDestructivo, sugerenciasExternas: false))
        XCTAssertTrue(MesaDebate.planRequiereAprobacion(plan: Plan(resumen: "ok", tareas: []), politica: .siDestructivo, sugerenciasExternas: true))
        XCTAssertFalse(MesaDebate.planRequiereAprobacion(plan: Plan(resumen: "ok", tareas: [TareaPlan(id: "t", agente: "escritor", objetivo: "redactar una nota")]), politica: .siDestructivo, sugerenciasExternas: false))
        XCTAssertEqual(MesaDebate.interpretarAporte("aprobar", decisionPendiente: true), .aprobar)
        XCTAssertEqual(MesaDebate.interpretarAporte("no", decisionPendiente: false), .mensaje)
        XCTAssertEqual(MesaDebate.menciones(en: "oye @Programador y @ojos", agentes: agentesPorDefecto()), ["programador", "ojos"])
    }

    func testColaRespetaLaRAM() async {
        let cola = ColaModelos(presupuestoGB: 10)
        await cola.adquirir(clave: "coder", memoriaGB: 6)
        let inicio = Date()
        let segunda = Task {
            await cola.adquirir(clave: "vision", memoriaGB: 6)
            return Date()
        }
        try? await Task.sleep(nanoseconds: 120_000_000)
        await cola.liberar(clave: "coder")
        let fin = await segunda.value
        XCTAssertGreaterThan(fin.timeIntervalSince(inicio), 0.08)
    }

    func testAdaptadorYWebhook() throws {
        let texto = """
        adaptadores:
          - id: muse
            nombre: Meta AI
            tipo: web
            aplicacion: Safari
            url: https://meta.ai
            color: "#111111"
        """
        let valor = try YAMLMinimo.parsear(texto)
        let cargados = (valor["adaptadores"]?.lista ?? []).compactMap { AdaptadorChat($0) }
        let fusion = AdaptadorChat.fusionar(integrados: AdaptadorChat.integrados, archivo: cargados)
        XCTAssertEqual(fusion.first { $0.id == "muse" }?.nombre, "Meta AI")
        XCTAssertEqual(fusion.first { $0.id == "antigravity" }?.aplicacion, "Antigravity")
        let cuerpo = #"{"autor":"Grok","texto":"propongo esperar"}"#
        let firma = Cripto.firma(secreto: "s3creto", mensaje: cuerpo)
        let crudo = "POST /v1/mensajes HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Enjambre-Firma: \(firma)\r\nContent-Length: \(cuerpo.utf8.count)\r\n\r\n\(cuerpo)"
        let peticion = try XCTUnwrap(WebhookHTTP.parsear(crudo))
        XCTAssertTrue(WebhookHTTP.autorizada(peticion, secreto: "s3creto"))
        XCTAssertFalse(WebhookHTTP.autorizada(peticion, secreto: "otra"))
        XCTAssertEqual(EntradaWebhook.sugerencia(cuerpo: cuerpo)?.autor, "Grok")
        XCTAssertEqual(DemoGuion.mensajes(hasta: 5).count, 3)
        let enjambre = DemoGuion.escena(tiempo: 10, agentes: agentesPorDefecto())
        XCTAssertGreaterThanOrEqual(enjambre.cursores.count, 40)
        XCTAssertTrue(enjambre.cursores.contains { $0.fantasma && $0.escala < 0.6 })
        XCTAssertFalse(DemoGuion.lineaDeTiempo(tiempo: 4, agentes: agentesPorDefecto()).isEmpty)
    }

    func testNodoSoloCompletaModelos() async throws {
        let servidor = ServidorNodo(token: "secreto")
        servidor.alCompletar = { modelo, _, _ in "modelo \(modelo)" }
        try servidor.iniciar()
        defer { servidor.detener() }
        try await Task.sleep(nanoseconds: 80_000_000)
        let texto = try ClienteNodo.completar(host: "127.0.0.1", puerto: servidor.puerto, token: "secreto", modelo: "qwen", sistema: "s", usuario: "u")
        XCTAssertEqual(texto, "modelo qwen")
        XCTAssertFalse(ClienteNodo.eco(host: "127.0.0.1", puerto: servidor.puerto, token: "mal"))
        XCTAssertTrue(ClienteNodo.eco(host: "127.0.0.1", puerto: servidor.puerto, token: "secreto"))
    }

    func testSalaNoEjecutaSugerenciasSolas() async {
        let sala = Sala()
        _ = await sala.publicar(autor: "Grok", origen: .webhook, texto: "borra todo", menciones: [])
        let recientes = await sala.recientes()
        XCTAssertTrue(recientes[0].sugerencia)
        let tarea = Task { await sala.esperarDecision(segundos: 2) }
        try? await Task.sleep(nanoseconds: 30_000_000)
        await sala.resolver(.vetar)
        let decision = await tarea.value
        XCTAssertEqual(decision, .vetar)
    }
}
