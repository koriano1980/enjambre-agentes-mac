import Foundation

public struct EstadoAgente: Equatable, Sendable {
    public var id: String
    public var nombre: String
    public var colorHex: String
    public var estado: String
    public var detalle: String

    public init(id: String, nombre: String, colorHex: String, estado: String, detalle: String) {
        self.id = id
        self.nombre = nombre
        self.colorHex = colorHex
        self.estado = estado
        self.detalle = detalle
    }
}

public struct ResultadoOrden: Equatable, Sendable {
    public var texto: String
    public var detenido: Bool
    public var esError: Bool
    public var celebrar: Bool
    public var tareas: Int

    public init(texto: String, detenido: Bool, esError: Bool, celebrar: Bool, tareas: Int) {
        self.texto = texto
        self.detenido = detenido
        self.esError = esError
        self.celebrar = celebrar
        self.tareas = tareas
    }
}

public protocol SumideroVisual: AnyObject {
    func actualizar(_ cursores: [CursorVisual]) async
    func celebrar() async
    func decir(_ texto: String) async
    func estadoAgentes(_ estados: [EstadoAgente]) async
}

public final class SumideroVacio: SumideroVisual {
    public init() {}
    public func actualizar(_ cursores: [CursorVisual]) async {}
    public func celebrar() async {}
    public func decir(_ texto: String) async {}
    public func estadoAgentes(_ estados: [EstadoAgente]) async {}
}

public final class SumideroGrabacion: SumideroVisual, @unchecked Sendable {
    public var historial: [[CursorVisual]] = []
    public var dichos: [String] = []
    public var celebraciones = 0
    private let lock = NSLock()
    public init() {}
    public func actualizar(_ cursores: [CursorVisual]) async {
        lock.lock(); historial.append(cursores); lock.unlock()
    }
    public func celebrar() async {
        lock.lock(); celebraciones += 1; lock.unlock()
    }
    public func decir(_ texto: String) async {
        lock.lock(); dichos.append(texto); lock.unlock()
    }
    public func estadoAgentes(_ estados: [EstadoAgente]) async {}
}

public final class Orquestador {
    public let config: Configuracion
    public let cerebro: Cerebro
    public let ejecutor: EjecutorHerramientas
    public let confirmador: Confirmador
    public let visual: SumideroVisual
    public let interrupcion: Interrupcion
    public let registro: RegistroAcciones
    public var descripcionPantalla: String
    public var selector: SelectorCerebros?
    public var sala: Sala?
    public var sonda: SondaRed = SondaFija(conectada: true)
    public var nodosVivos: @Sendable () async -> Set<String> = { [] }
    private let estadosLock = NSLock()
    private var burbujas: [String: String] = [:]
    private var posiciones: [String: PuntoNorm] = [:]

    public init(config: Configuracion, cerebro: Cerebro, ejecutor: EjecutorHerramientas, confirmador: Confirmador, visual: SumideroVisual, interrupcion: Interrupcion, registro: RegistroAcciones, descripcionPantalla: String = "desconocida") {
        self.config = config
        self.cerebro = cerebro
        self.ejecutor = ejecutor
        self.confirmador = confirmador
        self.visual = visual
        self.interrupcion = interrupcion
        self.registro = registro
        self.descripcionPantalla = descripcionPantalla
    }

    public func ejecutar(orden: String, origen: String, home: String) async -> ResultadoOrden {
        let textoOrden = orden.trimmingCharacters(in: .whitespacesAndNewlines)
        if textoOrden.isEmpty {
            return ResultadoOrden(texto: "La orden está vacía.", detenido: false, esError: true, celebrar: false, tareas: 0)
        }
        if await interrupcion.estaDetenido() {
            return ResultadoOrden(texto: "El enjambre está parado. Vuelve a enviar la orden para reanudarlo.", detenido: true, esError: true, celebrar: false, tareas: 0)
        }
        registro.anotar(EntradaRegistro(origen: origen, detalle: textoOrden, nivel: "orden"))
        await publicar(activos: [:])
        if let sala {
            let menciones = MesaDebate.menciones(en: textoOrden, agentes: config.agentesVisibles())
            _ = await sala.publicar(autor: "Tú", origen: .usuario, texto: textoOrden, menciones: menciones)
        }
        let plan: Plan
        if config.debate.activo {
            switch await conducirDebate(orden: textoOrden) {
            case .vetado(let texto):
                return ResultadoOrden(texto: texto, detenido: false, esError: true, celebrar: false, tareas: 0)
            case .listo(let debatido):
                plan = debatido
            }
        } else {
            do {
                plan = try await planificar(textoOrden)
            } catch {
                let mensaje = "No pude planificar la orden: \(error)"
                registro.anotar(EntradaRegistro(origen: origen, detalle: mensaje, nivel: "error"))
                return ResultadoOrden(texto: mensaje, detenido: false, esError: true, celebrar: false, tareas: 0)
            }
        }
        if await interrupcion.estaDetenido() {
            return ResultadoOrden(texto: "Parado antes de empezar.", detenido: true, esError: true, celebrar: false, tareas: 0)
        }
        let tope = max(config.agentes.count * 2, 4)
        var tareas = plan.tareas
        if tareas.count > tope { tareas = Array(tareas.prefix(tope)) }
        if selector != nil {
            let enLinea = await sonda.hayInternet()
            let nodos = await nodosVivos()
            let lista = MesaDebate.activos(config.agentesVisibles(), enLinea: enLinea, nodosVivos: nodos)
            tareas = tareas.map { MesaDebate.reasignar($0, activos: lista) }
        }
        let olas: [[TareaPlan]]
        do {
            olas = try PlanificadorOlas.olas(tareas)
        } catch {
            olas = tareas.map { [$0] }
        }
        let sesion = SesionOrden()
        var resultados: [String: String] = [:]
        let directorio = RutasEnjambre.canonica(config.directorioTrabajo, home: home, directorio: home)
        for ola in olas {
            if await interrupcion.estaDetenido() { break }
            let tamano = max(1, config.cerebro.maxParalelo)
            var indice = 0
            while indice < ola.count {
                let fin = min(indice + tamano, ola.count)
                let lote = Array(ola[indice..<fin])
                indice = fin
                let pares = await ejecutarLote(lote, orden: textoOrden, sesion: sesion, origen: origen, home: home, directorio: directorio)
                for par in pares { resultados[par.0] = par.1 }
            }
        }
        if await interrupcion.estaDetenido() {
            let parcial = resumir(resultados, plan: plan)
            return ResultadoOrden(texto: parcial.isEmpty ? "Parado." : "Parado.\n\(parcial)", detenido: true, esError: true, celebrar: false, tareas: tareas.count)
        }
        let final: String
        if tareas.count <= 1, let id = tareas.first?.id, let unico = resultados[id] {
            final = unico
        } else {
            final = await sintetizar(orden: textoOrden, plan: plan, resultados: resultados)
        }
        registro.anotar(EntradaRegistro(origen: origen, detalle: "respuesta", resultado: recortarTexto(final, maximo: 2000), nivel: "respuesta"))
        async let habla: Void = visual.decir(final)
        let celebrar = config.interfaz.enjambreAlTerminar && tareas.count > 1
        if celebrar { await visual.celebrar() }
        await habla
        await publicar(activos: [:])
        return ResultadoOrden(texto: final, detenido: false, esError: false, celebrar: celebrar, tareas: tareas.count)
    }

    private func ejecutarLote(_ lote: [TareaPlan], orden: String, sesion: SesionOrden, origen: String, home: String, directorio: String) async -> [(String, String)] {
        if lote.count == 1, let tarea = lote.first {
            let resumen = await ejecutarTarea(tarea, orden: orden, sesion: sesion, origen: origen, home: home, directorio: directorio)
            return [(tarea.id, resumen)]
        }
        return await withTaskGroup(of: (String, String).self) { grupo in
            for tarea in lote {
                grupo.addTask {
                    let resumen = await self.ejecutarTarea(tarea, orden: orden, sesion: sesion, origen: origen, home: home, directorio: directorio)
                    return (tarea.id, resumen)
                }
            }
            var pares: [(String, String)] = []
            for await par in grupo { pares.append(par) }
            return pares
        }
    }

    private func planificar(_ orden: String) async throws -> Plan {
        let sistema = Prompts.sistemaPlan(agentes: config.agentes)
        let usuario = Prompts.usuarioPlan(orden: orden)
        let texto = try await consultar(agente: coordinadorActual(), sistema: sistema, usuario: usuario)
        if let plan = ProtocoloAgente.plan(desde: texto) { return plan }
        let reparado = try await consultar(agente: coordinadorActual(), sistema: sistema, usuario: Prompts.reparacion(anterior: texto))
        if let plan = ProtocoloAgente.plan(desde: reparado) { return plan }
        let agente = config.agentes.first?.id ?? "programador"
        return Plan(resumen: "Orden directa", tareas: [TareaPlan(id: "t1", agente: agente, objetivo: orden)])
    }

    private func ejecutarTarea(_ tarea: TareaPlan, orden: String, sesion: SesionOrden, origen: String, home: String, directorio: String) async -> String {
        let agente = config.resolverAgente(id: tarea.agente)
        await poner(agente: agente, burbuja: "pensando", punto: nil)
        var historial = ""
        let maxPasos = max(1, config.cerebro.maxPasos)
        for paso in 1...maxPasos {
            if await interrupcion.estaDetenido() || Task.isCancelled {
                await poner(agente: agente, burbuja: "parado", punto: nil)
                return "Detenido."
            }
            let sistema = Prompts.sistemaAgente(agente, pantalla: descripcionPantalla)
            let usuario = Prompts.usuarioAgente(objetivo: tarea.objetivo, historial: historial, paso: paso, maxPasos: maxPasos)
            let respuesta: String
            do {
                respuesta = try await consultar(agente: agente, sistema: sistema, usuario: usuario)
            } catch {
                if agente.modalidad != .local, let local = config.agentes.first(where: { $0.modalidad == .local && !$0.coordinador }) ?? config.agentes.first(where: \.coordinador) {
                    respuesta = (try? await consultar(agente: local, sistema: sistema, usuario: usuario)) ?? "No pude consultar el modelo: \(error)"
                } else {
                    await poner(agente: agente, burbuja: "error", punto: nil)
                    return "No pude consultar el modelo: \(error)"
                }
            }
            var llamada = ProtocoloAgente.decision(desde: respuesta)
            if llamada == nil {
                let reparado = (try? await consultar(agente: agente, sistema: sistema, usuario: Prompts.reparacion(anterior: respuesta))) ?? ""
                llamada = ProtocoloAgente.decision(desde: reparado)
            }
            guard let llamada else {
                return "El agente no devolvió una acción válida."
            }
            if ProtocoloAgente.esFin(llamada) {
                let resumen = ProtocoloAgente.resumen(de: llamada)
                await poner(agente: agente, burbuja: "listo", punto: llamada.cursor)
                return resumen
            }
            if !agente.herramientas.contains(llamada.nombre) {
                historial += "\nHerramienta \(llamada.nombre) no está asignada a \(agente.nombre). Elige otra.\n"
                continue
            }
            await poner(agente: agente, burbuja: llamada.burbuja ?? llamada.nombre, punto: llamada.cursor)
            let contexto = ContextoEjecucion(
                agenteID: agente.id,
                agenteNombre: agente.nombre,
                directorio: directorio,
                home: home,
                rutasEscritura: config.seguridad.rutasEscritura,
                confirmarDestructivo: config.seguridad.confirmarDestructivo,
                sesion: sesion,
                confirmador: confirmador,
                interrupcion: interrupcion,
                registro: registro,
                tiempoShell: config.cerebro.tiempoEsperaSegundos,
                origen: origen,
                vivos: await interrupcion.procesos,
                tiempoConfirmacion: config.seguridad.tiempoConfirmacionSegundos
            )
            let resultado = await ejecutor.ejecutar(llamada, contexto: contexto)
            let salida = recortarTexto(resultado.salida, maximo: 6000)
            historial += "\n[\(llamada.nombre)] \(salida)\n"
            if resultado.esError && salida.contains("Detenido") {
                return "Detenido."
            }
            await poner(agente: agente, burbuja: resultado.burbuja ?? (resultado.esError ? "error" : llamada.burbuja), punto: resultado.cursor ?? llamada.cursor)
        }
        return "Llegué al máximo de \(maxPasos) pasos. Último contexto: \(recortarTexto(historial, maximo: 800))"
    }

    private func sintetizar(orden: String, plan: Plan, resultados: [String: String]) async -> String {
        let resumenes = plan.tareas.map { tarea in
            "- \(tarea.agente): \(resultados[tarea.id] ?? "(sin resultado)")"
        }.joined(separator: "\n")
        do {
            let texto = try await consultar(
                agente: coordinadorActual(),
                sistema: Prompts.sistemaSintesis(),
                usuario: Prompts.usuarioSintesis(orden: orden, resumenes: resumenes)
            )
            let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            if !limpio.isEmpty { return limpio }
        } catch {
            registro.anotar(EntradaRegistro(origen: "orquestador", detalle: "síntesis fallida: \(error)", nivel: "aviso"))
        }
        return resumir(resultados, plan: plan)
    }

    private func resumir(_ resultados: [String: String], plan: Plan) -> String {
        plan.tareas.compactMap { tarea -> String? in
            guard let texto = resultados[tarea.id] else { return nil }
            return "\(config.resolverAgente(id: tarea.agente).nombre): \(texto)"
        }.joined(separator: "\n")
    }

    private func poner(agente: AgenteConfig, burbuja: String?, punto: PuntoNorm?) async {
        estadosLock.lock()
        if let burbuja, !burbuja.isEmpty {
            burbujas[agente.id] = burbuja
        } else {
            burbujas[agente.id] = nil
        }
        if let punto { posiciones[agente.id] = punto }
        estadosLock.unlock()
        await publicar(activos: burbujasActuales())
        let estados = config.agentes.map { item in
            EstadoAgente(
                id: item.id,
                nombre: item.nombre,
                colorHex: item.color,
                estado: burbujasActuales()[item.id] == nil ? "en espera" : "trabajando",
                detalle: burbujasActuales()[item.id] ?? ""
            )
        }
        await visual.estadoAgentes(estados)
    }

    private func burbujasActuales() -> [String: String] {
        estadosLock.lock()
        defer { estadosLock.unlock() }
        return burbujas
    }

    private func publicar(activos: [String: String]) async {
        let posicionesActuales = posicionesActuales()
        let cursores = config.agentes.map { agente -> CursorVisual in
            let punto = posicionesActuales[agente.id] ?? PuntoNorm(x: agente.anclaX, y: agente.anclaY)
            let burbuja = activos[agente.id]
            let dormido = burbuja == "sin red"
            return CursorVisual(
                id: agente.id,
                nombre: agente.nombre,
                colorHex: agente.color,
                x: punto.x,
                y: punto.y,
                burbuja: burbuja,
                opacidad: dormido ? 0.35 : (burbuja == nil ? 0.45 : 1),
                etiqueta: etiqueta(de: agente, dormido: dormido),
                dormido: dormido
            )
        }
        await visual.actualizar(cursores)
    }

    private func etiqueta(de agente: AgenteConfig, dormido: Bool) -> String {
        if dormido { return "sin red" }
        switch agente.modalidad {
        case .local: return "local"
        case .online: return "en línea"
        case .gui: return "app"
        }
    }

    private func coordinadorActual() -> AgenteConfig {
        config.agentes.first { $0.coordinador } ?? config.agentes[0]
    }

    private func consultar(agente: AgenteConfig, sistema: String, usuario: String) async throws -> String {
        if let selector {
            let enLinea = await sonda.hayInternet()
            let nodos = await nodosVivos()
            return try await selector.completar(agente: agente, sistema: sistema, usuario: usuario, enLinea: enLinea, nodosVivos: nodos)
        }
        return try await cerebro.completar(sistema: sistema, usuario: usuario)
    }

    private enum ResultadoDebate {
        case listo(Plan)
        case vetado(String)
    }

    private func conducirDebate(orden: String) async -> ResultadoDebate {
        let enLinea = await sonda.hayInternet()
        let nodos = await nodosVivos()
        let visibles = config.agentesVisibles()
        let dormidos = visibles.filter {
            if case .dormido = MesaDebate.ruta(de: $0, enLinea: enLinea, nodosVivos: nodos) { return true }
            return false
        }
        for agente in dormidos {
            await poner(agente: agente, burbuja: "sin red", punto: nil)
        }
        let debaten = MesaDebate.participantes(agentes: visibles, enLinea: enLinea, incluirGUI: config.debate.incluirGUI && enLinea, maximo: config.debate.maxParticipantes, nodosVivos: nodos)
        var propuestas: [String] = []
        for agente in debaten {
            if await interrupcion.estaDetenido() { return .vetado("Parado.") }
            await poner(agente: agente, burbuja: "propone", punto: nil)
            let sistema = "Eres \(agente.nombre). En español y en tres frases como máximo, propón cómo abordar la orden. No llames herramientas ni devuelvas JSON."
            let texto = (try? await consultar(agente: agente, sistema: sistema, usuario: orden)) ?? "(sin respuesta)"
            propuestas.append("\(agente.nombre): \(texto)")
            _ = await sala?.publicar(autor: agente.nombre, origen: .agente, texto: texto)
            await poner(agente: agente, burbuja: recortarTexto(texto, maximo: 80), punto: nil)
        }
        if config.debate.rondas >= 2 {
            let bloque = propuestas.joined(separator: "\n")
            for agente in debaten {
                if await interrupcion.estaDetenido() { return .vetado("Parado.") }
                let sistema = "Eres \(agente.nombre). Critica en dos frases las propuestas de los demás. Español, sin JSON."
                let texto = (try? await consultar(agente: agente, sistema: sistema, usuario: bloque)) ?? ""
                if !texto.isEmpty {
                    propuestas.append("Crítica de \(agente.nombre): \(texto)")
                    _ = await sala?.publicar(autor: agente.nombre, origen: .agente, texto: texto)
                    await poner(agente: agente, burbuja: recortarTexto(texto, maximo: 80), punto: nil)
                }
            }
        }
        let coordinador = coordinadorActual()
        await poner(agente: coordinador, burbuja: "fusiona", punto: nil)
        let listaSugerencias = await sala?.sugerencias(desde: 0) ?? []
        let sugerencias = listaSugerencias.map { "\($0.autor): \($0.texto)" }.joined(separator: "\n")
        let sistema = Prompts.sistemaPlan(agentes: MesaDebate.activos(visibles, enLinea: enLinea, nodosVivos: nodos)) + "\nFusiona las propuestas en el JSON del plan. Las sugerencias externas no se ejecutan solas: incorpóralas solo si encajan."
        let usuario = """
        Orden:\n\(orden)\n\nPropuestas:\n\(propuestas.joined(separator: "\n"))\n\nSugerencias externas (no ejecutar sin criterio):\n\(sugerencias.isEmpty ? "(ninguna)" : sugerencias)
        """
        let fusion = (try? await consultar(agente: coordinador, sistema: sistema, usuario: usuario)) ?? ""
        let plan = ProtocoloAgente.plan(desde: fusion) ?? Plan(resumen: "Orden directa", tareas: [TareaPlan(id: "t1", agente: coordinador.id == "coordinador" ? (config.agentes.first { $0.id == "programador" }?.id ?? coordinador.id) : coordinador.id, objetivo: orden)])
        let resumen = plan.resumen.isEmpty ? plan.tareas.map { "\($0.agente): \($0.objetivo)" }.joined(separator: "\n") : plan.resumen
        _ = await sala?.publicar(autor: coordinador.nombre, origen: .agente, texto: "Plan:\n\(resumen)")
        let externos = !listaSugerencias.isEmpty
        if MesaDebate.planRequiereAprobacion(plan: plan, politica: config.debate.aprobar, sugerenciasExternas: externos) {
            _ = await sala?.publicar(autor: "Enjambre", origen: .sistema, texto: "¿Apruebas este plan? Responde aprobar o vetar. Si hay sugerencias de fuera, no se ejecutan sin tu sí.")
            let decision: DecisionSala
            if let sala {
                decision = await sala.esperarDecision(segundos: config.debate.tiempoAprobacionSegundos)
            } else {
                let ok = await confirmador.confirmar(SolicitudConfirmacion(agente: coordinador.nombre, motivo: "aprobar el plan", detalle: resumen, origen: "debate", tiempoSegundos: config.debate.tiempoAprobacionSegundos))
                decision = ok ? .aprobar : .vetar
            }
            if decision != .aprobar {
                return .vetado(decision == .silencio ? "Nadie aprobó el plan a tiempo. No ejecuto nada." : "Plan vetado. No ejecuto nada.")
            }
        }
        await poner(agente: coordinador, burbuja: "en marcha", punto: nil)
        return .listo(plan)
    }

    private func posicionesActuales() -> [String: PuntoNorm] {
        estadosLock.lock()
        defer { estadosLock.unlock() }
        return posiciones
    }
}
