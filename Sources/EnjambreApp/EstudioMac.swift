#if os(macOS)
import AppKit
import EnjambreNucleo

/// Ventana principal con la disposición del estudio del reel: lista, previsualización, inspector y línea de tiempo.
final class VentanaEstudio {
    private var ventana: NSWindow?
    private var vista: VistaEstudio?
    private var timer: Timer?
    private var demo = false
    private var tiempo = 0.0
    private var agentes: [AgenteConfig] = []

    func mostrar(agentes: [AgenteConfig]) {
        self.agentes = agentes
        if ventana == nil { construir() }
        vista?.agentes = agentes
        ventana?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func reproducirDemo(agentes: [AgenteConfig]) {
        self.agentes = agentes
        mostrar(agentes: agentes)
        demo = true
        tiempo = 0
        if timer == nil {
            let temporizador = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(temporizador, forMode: .common)
            timer = temporizador
        }
    }

    func detenerDemo() {
        demo = false
    }

    func aplicarEstados(_ estados: [EstadoAgente], aviso: String) {
        demo = false
        vista?.aviso = aviso
        vista?.estados = estados
        vista?.needsDisplay = true
    }

    private func tick() {
        guard demo else { return }
        tiempo += 1.0 / 30.0
        let escena = DemoGuion.escena(tiempo: tiempo, agentes: agentes)
        vista?.aviso = escena.aviso
        vista?.bloques = DemoGuion.lineaDeTiempo(tiempo: tiempo, agentes: agentes)
        vista?.mensaje = DemoGuion.mensajes(hasta: tiempo).last?.texto
        vista?.needsDisplay = true
    }

    private func construir() {
        let ventana = NSWindow(
            contentRect: NSRect(x: 80, y: 60, width: 1180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        ventana.title = "Enjambre"
        ventana.minSize = NSSize(width: 960, height: 640)
        ventana.backgroundColor = NSColor(srgbRed: 0.07, green: 0.08, blue: 0.09, alpha: 1)
        ventana.titlebarAppearsTransparent = true
        ventana.isMovableByWindowBackground = true
        let vista = VistaEstudio(frame: ventana.contentView?.bounds ?? .zero)
        vista.autoresizingMask = [.width, .height]
        ventana.contentView = vista
        self.ventana = ventana
        self.vista = vista
    }
}

private final class VistaEstudio: NSView {
    var agentes: [AgenteConfig] = []
    var estados: [EstadoAgente] = []
    var bloques: [BloqueLinea] = []
    var aviso: String?
    var mensaje: String?
    private var seleccionado = 0

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let punto = convert(event.locationInWindow, from: nil)
        let fila = (punto.y - 56) / 36
        if punto.x < 220, fila >= 0, Int(fila) < agentes.count {
            seleccionado = Int(fila)
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let fondo = NSColor(srgbRed: 0.055, green: 0.062, blue: 0.075, alpha: 1)
        fondo.setFill()
        bounds.fill()
        let anchoLista: CGFloat = 220
        let anchoInspector: CGFloat = 280
        let altoTiempo: CGFloat = 210
        let altoBarra: CGFloat = 46
        let cuerpo = NSRect(x: 0, y: altoBarra, width: bounds.width, height: bounds.height - altoBarra - altoTiempo)
        dibujarBarra(NSRect(x: 0, y: 0, width: bounds.width, height: altoBarra))
        dibujarLista(NSRect(x: 0, y: cuerpo.minY, width: anchoLista, height: cuerpo.height))
        dibujarPreview(NSRect(x: anchoLista, y: cuerpo.minY, width: bounds.width - anchoLista - anchoInspector, height: cuerpo.height))
        dibujarInspector(NSRect(x: bounds.width - anchoInspector, y: cuerpo.minY, width: anchoInspector, height: cuerpo.height))
        dibujarTiempo(NSRect(x: 0, y: bounds.height - altoTiempo, width: bounds.width, height: altoTiempo))
    }

    private func dibujarBarra(_ rect: NSRect) {
        NSColor(srgbRed: 0.09, green: 0.10, blue: 0.12, alpha: 1).setFill()
        rect.fill()
        NSColor(srgbRed: 0.16, green: 0.18, blue: 0.22, alpha: 1).setFill()
        NSRect(x: 0, y: rect.maxY - 1, width: rect.width, height: 1).fill()
        let titulo = "Enjambre" as NSString
        titulo.draw(at: NSPoint(x: 16, y: 14), withAttributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        let sub = (aviso ?? "Estudio") as NSString
        sub.draw(at: NSPoint(x: 120, y: 16), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor(srgbRed: 0.62, green: 0.66, blue: 0.72, alpha: 1),
        ])
    }

    private func dibujarLista(_ rect: NSRect) {
        NSColor(srgbRed: 0.07, green: 0.08, blue: 0.095, alpha: 1).setFill()
        rect.fill()
        ("Agentes" as NSString).draw(at: NSPoint(x: rect.minX + 14, y: rect.minY + 12), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(srgbRed: 0.55, green: 0.60, blue: 0.66, alpha: 1),
        ])
        for (indice, agente) in agentes.enumerated() {
            let fila = NSRect(x: rect.minX + 8, y: rect.minY + 36 + CGFloat(indice) * 36, width: rect.width - 16, height: 32)
            if indice == seleccionado {
                NSColor(srgbRed: 0.14, green: 0.17, blue: 0.22, alpha: 1).setFill()
                NSBezierPath(roundedRect: fila, xRadius: 6, yRadius: 6).fill()
            }
            colorHex(agente.color).setFill()
            NSBezierPath(ovalIn: NSRect(x: fila.minX + 8, y: fila.minY + 11, width: 8, height: 8)).fill()
            (agente.nombre as NSString).draw(at: NSPoint(x: fila.minX + 24, y: fila.minY + 8), withAttributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.white,
            ])
        }
    }

    private func dibujarPreview(_ rect: NSRect) {
        NSColor(srgbRed: 0.04, green: 0.045, blue: 0.055, alpha: 1).setFill()
        rect.fill()
        let lienzo = rect.insetBy(dx: 28, dy: 36)
        NSColor(srgbRed: 0.09, green: 0.10, blue: 0.12, alpha: 1).setFill()
        NSBezierPath(roundedRect: lienzo, xRadius: 10, yRadius: 10).fill()
        let agente = agentes.indices.contains(seleccionado) ? agentes[seleccionado] : nil
        let titulo = agente?.nombre ?? "Previsualización"
        (titulo as NSString).draw(at: NSPoint(x: lienzo.minX + 16, y: lienzo.minY + 16), withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor(srgbRed: 0.75, green: 0.8, blue: 0.86, alpha: 1),
        ])
        let texto = mensaje ?? "Aquí se ve lo que hace el agente activo: la app, el archivo o el texto en curso."
        let estilo = NSMutableParagraphStyle()
        estilo.lineBreakMode = .byWordWrapping
        (texto as NSString).draw(in: NSRect(x: lienzo.minX + 16, y: lienzo.midY - 20, width: lienzo.width - 32, height: 80), withAttributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.white,
            .paragraphStyle: estilo,
        ])
    }

    private func dibujarInspector(_ rect: NSRect) {
        NSColor(srgbRed: 0.08, green: 0.09, blue: 0.11, alpha: 1).setFill()
        rect.fill()
        ("Inspector" as NSString).draw(at: NSPoint(x: rect.minX + 16, y: rect.minY + 14), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(srgbRed: 0.55, green: 0.60, blue: 0.66, alpha: 1),
        ])
        guard agentes.indices.contains(seleccionado) else { return }
        let agente = agentes[seleccionado]
        let estado = estados.first { $0.id == agente.id }
        let lineas = [
            agente.nombre,
            "Modalidad: \(agente.modalidad.rawValue)",
            "Modelo: \(agente.modelo.isEmpty ? "según la red" : agente.modelo)",
            "Proveedor: \(agente.proveedor.rawValue)",
            "Estado: \(estado?.detalle.isEmpty == false ? (estado?.detalle ?? "") : (estado?.estado ?? "en espera"))",
        ]
        for (indice, linea) in lineas.enumerated() {
            (linea as NSString).draw(at: NSPoint(x: rect.minX + 16, y: rect.minY + 48 + CGFloat(indice) * 28), withAttributes: [
                .font: NSFont.systemFont(ofSize: indice == 0 ? 16 : 12, weight: indice == 0 ? .semibold : .regular),
                .foregroundColor: indice == 0 ? NSColor.white : NSColor(srgbRed: 0.78, green: 0.82, blue: 0.86, alpha: 1),
            ])
        }
    }

    private func dibujarTiempo(_ rect: NSRect) {
        NSColor(srgbRed: 0.06, green: 0.07, blue: 0.085, alpha: 1).setFill()
        rect.fill()
        NSColor(srgbRed: 0.2, green: 0.55, blue: 0.62, alpha: 1).setFill()
        NSRect(x: 0, y: rect.minY, width: rect.width, height: 2).fill()
        ("Línea de tiempo" as NSString).draw(at: NSPoint(x: 16, y: rect.minY + 8), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(srgbRed: 0.55, green: 0.6, blue: 0.66, alpha: 1),
        ])
        let carriles = max(agentes.count, 1)
        let alto = min(22, (rect.height - 36) / CGFloat(carriles))
        for (indice, agente) in agentes.enumerated() {
            let y = rect.minY + 28 + CGFloat(indice) * (alto + 4)
            (agente.nombre as NSString).draw(at: NSPoint(x: 12, y: y + 2), withAttributes: [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: NSColor(white: 0.75, alpha: 1),
            ])
            guard let bloque = bloques.first(where: { $0.agenteID == agente.id }) else { continue }
            let origen = 120 + rect.width * 0.55 * bloque.inicio
            let ancho = max(8, (rect.width - 160) * bloque.duracion)
            let pista = NSRect(x: origen, y: y, width: ancho, height: alto)
            colorHex(agente.color).withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: pista, xRadius: 4, yRadius: 4).fill()
            let lleno = NSRect(x: pista.minX, y: pista.minY, width: pista.width * bloque.progreso, height: pista.height)
            colorHex(agente.color).setFill()
            NSBezierPath(roundedRect: lleno, xRadius: 4, yRadius: 4).fill()
        }
    }
}
#endif
