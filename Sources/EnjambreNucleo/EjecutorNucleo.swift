import Foundation

public struct SolicitudConfirmacion: Sendable {
    public var agente: String
    public var motivo: String
    public var detalle: String
    public var origen: String
    public var tiempoSegundos: Double

    public init(agente: String, motivo: String, detalle: String, origen: String, tiempoSegundos: Double) {
        self.agente = agente
        self.motivo = motivo
        self.detalle = detalle
        self.origen = origen
        self.tiempoSegundos = tiempoSegundos
    }
}

public protocol Confirmador: AnyObject {
    func confirmar(_ solicitud: SolicitudConfirmacion) async -> Bool
}

public final class ConfirmadorFijo: Confirmador {
    public var valor: Bool
    public init(valor: Bool) { self.valor = valor }
    public func confirmar(_ solicitud: SolicitudConfirmacion) async -> Bool { valor }
}

public actor SesionOrden {
    private var guiAutorizado = false
    private var preguntaEnCurso: Task<Bool, Never>?

    public init() {}

    /// Una sola pregunta de control de interfaz por orden, compartida por los agentes en paralelo.
    public func autorizarSiHaceFalta(_ preguntar: @escaping () async -> Bool) async -> Bool {
        if guiAutorizado { return true }
        if let preguntaEnCurso {
            return await preguntaEnCurso.value
        }
        let tarea = Task { await preguntar() }
        preguntaEnCurso = tarea
        let ok = await tarea.value
        if ok { guiAutorizado = true }
        preguntaEnCurso = nil
        return ok
    }
}

public struct ContextoEjecucion {
    public var agenteID: String
    public var agenteNombre: String
    public var directorio: String
    public var home: String
    public var rutasEscritura: [String]
    public var confirmarDestructivo: Bool
    public var sesion: SesionOrden
    public var confirmador: Confirmador
    public var interrupcion: Interrupcion
    public var registro: RegistroAcciones
    public var tiempoShell: TimeInterval
    public var origen: String
    public var vivos: ProcesosVivos
    public var tiempoConfirmacion: TimeInterval

    public init(agenteID: String, agenteNombre: String, directorio: String, home: String, rutasEscritura: [String], confirmarDestructivo: Bool, sesion: SesionOrden, confirmador: Confirmador, interrupcion: Interrupcion, registro: RegistroAcciones, tiempoShell: TimeInterval, origen: String, vivos: ProcesosVivos, tiempoConfirmacion: TimeInterval = 45) {
        self.agenteID = agenteID
        self.agenteNombre = agenteNombre
        self.directorio = directorio
        self.home = home
        self.rutasEscritura = rutasEscritura
        self.confirmarDestructivo = confirmarDestructivo
        self.sesion = sesion
        self.confirmador = confirmador
        self.interrupcion = interrupcion
        self.registro = registro
        self.tiempoShell = tiempoShell
        self.origen = origen
        self.vivos = vivos
        self.tiempoConfirmacion = tiempoConfirmacion
    }
}

public protocol HerramientaExtra: AnyObject {
    var nombres: [String] { get }
    func ejecutar(_ llamada: LlamadaHerramienta, contexto: ContextoEjecucion) async -> ResultadoHerramienta
}

public protocol EjecutorHerramientas: AnyObject {
    func ejecutar(_ llamada: LlamadaHerramienta, contexto: ContextoEjecucion) async -> ResultadoHerramienta
}

public final class EjecutorNucleo: EjecutorHerramientas {
    public var extra: HerramientaExtra?
    public init(extra: HerramientaExtra? = nil) { self.extra = extra }

    public func ejecutar(_ llamada: LlamadaHerramienta, contexto: ContextoEjecucion) async -> ResultadoHerramienta {
        if await contexto.interrupcion.estaDetenido() || Task.isCancelled {
            return ResultadoHerramienta(salida: "Detenido por el interruptor.", esError: true)
        }
        switch llamada.nombre {
        case "shell":
            return await shell(llamada, contexto)
        case "leer_archivo":
            return await leer(llamada, contexto)
        case "escribir_archivo":
            return await escribir(llamada, contexto)
        case "editar_archivo":
            return await editar(llamada, contexto)
        case "listar":
            return await listar(llamada, contexto)
        case "esperar":
            return await esperar(llamada, contexto)
        default:
            guard let extra, extra.nombres.contains(llamada.nombre) else {
                return ResultadoHerramienta(salida: "Herramienta desconocida: \(llamada.nombre)", esError: true)
            }
            return await extra.ejecutar(llamada, contexto: contexto)
        }
    }
}

public func exigirRiesgo(_ nivel: NivelRiesgo, detalle: String, contexto: ContextoEjecucion, herramienta: String) async -> ResultadoHerramienta? {
    switch nivel {
    case .permitido:
        return nil
    case .rechazado(let motivo):
        contexto.registro.anotar(EntradaRegistro(origen: contexto.origen, agente: contexto.agenteNombre, herramienta: herramienta, detalle: detalle, resultado: motivo, nivel: "rechazado"))
        return ResultadoHerramienta(salida: "Rechazado: \(motivo).", esError: true)
    case .confirmar(let motivo):
        guard contexto.confirmarDestructivo else { return nil }
        contexto.registro.anotar(EntradaRegistro(origen: contexto.origen, agente: contexto.agenteNombre, herramienta: herramienta, detalle: detalle, resultado: "pidiendo confirmación: \(motivo)", nivel: "confirmar"))
        let ok = await contexto.confirmador.confirmar(solicitud(motivo, detalle: detalle, contexto: contexto))
        if !ok {
            return ResultadoHerramienta(salida: "Denegado por el usuario: \(motivo).", esError: true)
        }
        return nil
    case .autorizarGUI(let motivo):
        guard contexto.confirmarDestructivo else { return nil }
        let ok = await contexto.sesion.autorizarSiHaceFalta {
            await contexto.confirmador.confirmar(solicitud(motivo, detalle: detalle, contexto: contexto))
        }
        if !ok {
            return ResultadoHerramienta(salida: "El usuario no autorizó el control de la interfaz.", esError: true)
        }
        return nil
    }
}

private func solicitud(_ motivo: String, detalle: String, contexto: ContextoEjecucion) -> SolicitudConfirmacion {
    SolicitudConfirmacion(
        agente: contexto.agenteNombre,
        motivo: motivo,
        detalle: recortarTexto(detalle, maximo: 1200),
        origen: contexto.origen,
        tiempoSegundos: contexto.tiempoConfirmacion
    )
}

private func shell(_ llamada: LlamadaHerramienta, _ contexto: ContextoEjecucion) async -> ResultadoHerramienta {
    guard let comando = llamada.texto("comando") ?? llamada.texto("cmd"), !comando.trimmingCharacters(in: .whitespaces).isEmpty else {
        return ResultadoHerramienta(salida: "Falta el argumento comando.", esError: true)
    }
    let nivel = Seguridad.evaluarComandoShell(comando)
    if let bloqueo = await exigirRiesgo(nivel, detalle: comando, contexto: contexto, herramienta: "shell") {
        return bloqueo
    }
    if await contexto.interrupcion.estaDetenido() { return ResultadoHerramienta(salida: "Detenido por el interruptor.", esError: true) }
    let directorio = llamada.texto("directorio").map { RutasEnjambre.canonica($0, home: contexto.home, directorio: contexto.directorio) } ?? contexto.directorio
    contexto.registro.anotar(EntradaRegistro(origen: contexto.origen, agente: contexto.agenteNombre, herramienta: "shell", detalle: comando, nivel: "accion"))
    let resultado = LanzadorProceso.ejecutar(
        ejecutable: shellDelSistema(),
        argumentos: ["-c", comando],
        directorio: directorio,
        entorno: entornoConRutasHabituales(home: contexto.home),
        tiempoLimite: contexto.tiempoShell,
        vivos: contexto.vivos
    )
    if resultado.detenido {
        return ResultadoHerramienta(salida: "Detenido por el interruptor.", esError: true)
    }
    var texto = resultado.salida
    if !resultado.error.isEmpty {
        texto += (texto.isEmpty ? "" : "\n") + resultado.error
    }
    if resultado.excedioTiempo {
        texto += "\nSe agotó el tiempo de espera."
    }
    let error = resultado.codigo != 0 || resultado.excedioTiempo
    return ResultadoHerramienta(salida: recortarTexto(texto.isEmpty ? "código \(resultado.codigo)" : texto, maximo: 20000), esError: error)
}

private func leer(_ llamada: LlamadaHerramienta, _ contexto: ContextoEjecucion) async -> ResultadoHerramienta {
    guard let rutaDada = llamada.texto("ruta") else {
        return ResultadoHerramienta(salida: "Falta la ruta.", esError: true)
    }
    let ruta = rutaReal(rutaDada, contexto)
    let nivel = Seguridad.evaluarRutaLectura(ruta, home: contexto.home, directorio: contexto.directorio)
    if let bloqueo = await exigirRiesgo(nivel, detalle: ruta, contexto: contexto, herramienta: "leer_archivo") {
        return bloqueo
    }
    do {
        let texto = try String(contentsOfFile: ruta, encoding: .utf8)
        contexto.registro.anotar(EntradaRegistro(origen: contexto.origen, agente: contexto.agenteNombre, herramienta: "leer_archivo", detalle: ruta, nivel: "accion"))
        return ResultadoHerramienta(salida: recortarTexto(texto, maximo: 80000))
    } catch {
        return ResultadoHerramienta(salida: "No se pudo leer \(ruta): \(error.localizedDescription)", esError: true)
    }
}

private func escribir(_ llamada: LlamadaHerramienta, _ contexto: ContextoEjecucion) async -> ResultadoHerramienta {
    guard let rutaDada = llamada.texto("ruta") else {
        return ResultadoHerramienta(salida: "Falta la ruta.", esError: true)
    }
    let contenido = llamada.texto("contenido") ?? ""
    let ruta = rutaReal(rutaDada, contexto)
    let nivel = Seguridad.evaluarRutaEscritura(ruta, permitidas: contexto.rutasEscritura, home: contexto.home, directorio: contexto.directorio)
    if let bloqueo = await exigirRiesgo(nivel, detalle: ruta, contexto: contexto, herramienta: "escribir_archivo") {
        return bloqueo
    }
    do {
        let url = URL(fileURLWithPath: ruta)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contenido.write(to: url, atomically: true, encoding: .utf8)
        contexto.registro.anotar(EntradaRegistro(origen: contexto.origen, agente: contexto.agenteNombre, herramienta: "escribir_archivo", detalle: ruta, resultado: "\(contenido.count) caracteres", nivel: "accion"))
        return ResultadoHerramienta(salida: "Escrito \(ruta) (\(contenido.count) caracteres).")
    } catch {
        return ResultadoHerramienta(salida: "No se pudo escribir \(ruta): \(error.localizedDescription)", esError: true)
    }
}

private func editar(_ llamada: LlamadaHerramienta, _ contexto: ContextoEjecucion) async -> ResultadoHerramienta {
    guard let rutaDada = llamada.texto("ruta"), let buscar = llamada.texto("buscar") else {
        return ResultadoHerramienta(salida: "Faltan ruta y buscar.", esError: true)
    }
    if buscar.isEmpty { return ResultadoHerramienta(salida: "buscar no puede estar vacío.", esError: true) }
    let reemplazar = llamada.texto("reemplazar") ?? ""
    let ruta = rutaReal(rutaDada, contexto)
    let nivel = Seguridad.evaluarRutaEscritura(ruta, permitidas: contexto.rutasEscritura, home: contexto.home, directorio: contexto.directorio)
    if let bloqueo = await exigirRiesgo(nivel, detalle: ruta, contexto: contexto, herramienta: "editar_archivo") {
        return bloqueo
    }
    do {
        var texto = try String(contentsOfFile: ruta, encoding: .utf8)
        let todas = llamada.bool("todas") ?? false
        let veces: Int
        if todas {
            let trozos = texto.components(separatedBy: buscar)
            veces = trozos.count - 1
            texto = trozos.joined(separator: reemplazar)
        } else if let rango = texto.range(of: buscar) {
            texto.replaceSubrange(rango, with: reemplazar)
            veces = 1
        } else {
            veces = 0
        }
        if veces == 0 {
            return ResultadoHerramienta(salida: "No encontré el texto en \(ruta).", esError: true)
        }
        try texto.write(toFile: ruta, atomically: true, encoding: .utf8)
        contexto.registro.anotar(EntradaRegistro(origen: contexto.origen, agente: contexto.agenteNombre, herramienta: "editar_archivo", detalle: ruta, resultado: "\(veces) reemplazo(s)", nivel: "accion"))
        return ResultadoHerramienta(salida: "Actualicé \(ruta) (\(veces) reemplazo(s)).")
    } catch {
        return ResultadoHerramienta(salida: "No se pudo editar \(ruta): \(error.localizedDescription)", esError: true)
    }
}

private func listar(_ llamada: LlamadaHerramienta, _ contexto: ContextoEjecucion) async -> ResultadoHerramienta {
    let rutaDada = llamada.texto("ruta") ?? contexto.directorio
    let ruta = rutaReal(rutaDada, contexto)
    let nivel = Seguridad.evaluarRutaLectura(ruta, home: contexto.home, directorio: contexto.directorio)
    if let bloqueo = await exigirRiesgo(nivel, detalle: ruta, contexto: contexto, herramienta: "listar") {
        return bloqueo
    }
    do {
        let urls = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: ruta), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        let lineas = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.prefix(400).map { url -> String in
            let directorio = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return (directorio ? "d " : "f ") + url.lastPathComponent
        }
        contexto.registro.anotar(EntradaRegistro(origen: contexto.origen, agente: contexto.agenteNombre, herramienta: "listar", detalle: ruta, nivel: "accion"))
        if lineas.isEmpty { return ResultadoHerramienta(salida: "(vacío) \(ruta)") }
        return ResultadoHerramienta(salida: lineas.joined(separator: "\n"))
    } catch {
        return ResultadoHerramienta(salida: "No se pudo listar \(ruta): \(error.localizedDescription)", esError: true)
    }
}

private func esperar(_ llamada: LlamadaHerramienta, _ contexto: ContextoEjecucion) async -> ResultadoHerramienta {
    let pedido = llamada.numero("segundos") ?? 1
    let segundos = min(10, max(0, pedido))
    let pasos = Int(segundos / 0.1)
    for _ in 0..<max(pasos, 0) {
        if await contexto.interrupcion.estaDetenido() {
            return ResultadoHerramienta(salida: "Detenido por el interruptor.", esError: true)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return ResultadoHerramienta(salida: "Esperé \(segundos) s.")
}

func rutaReal(_ ruta: String, _ contexto: ContextoEjecucion) -> String {
    let canonica = RutasEnjambre.canonica(ruta, home: contexto.home, directorio: contexto.directorio)
    let url = URL(fileURLWithPath: canonica)
    let padre = url.deletingLastPathComponent().resolvingSymlinksInPath()
    return padre.appendingPathComponent(url.lastPathComponent).path
}
