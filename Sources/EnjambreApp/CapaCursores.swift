#if os(macOS)
import AppKit
import EnjambreNucleo

final class CapaCursores {
    private var ventana: NSWindow?
    private var vista: VistaCursores?
    private var timer: Timer?
    private var demo = false
    private var tiempoDemo = 0.0
    private var agentes: [AgenteConfig] = []
    private var alMensajeDemo: ((String, String) -> Void)?

    func iniciar() {
        if ventana != nil { return }
        let vista = VistaCursores()
        let ventana = VentanaCapa(contentRect: rectanguloGlobal(), styleMask: .borderless, backing: .buffered, defer: false)
        ventana.isOpaque = false
        ventana.backgroundColor = .clear
        ventana.ignoresMouseEvents = true
        ventana.level = .screenSaver
        ventana.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ventana.sharingType = .none
        ventana.hasShadow = false
        ventana.isReleasedWhenClosed = false
        ventana.contentView = vista
        ventana.orderFrontRegardless()
        self.ventana = ventana
        self.vista = vista
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.ventana?.setFrame(self?.rectanguloGlobal() ?? .zero, display: true)
        }
        let temporizador = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(temporizador, forMode: .common)
        timer = temporizador
    }

    func fijar(_ cursores: [CursorVisual], aviso: String?) {
        demo = false
        vista?.aviso = aviso
        vista?.aplicar(cursores)
    }

    func reproducirDemo(agentes: [AgenteConfig], alMensaje: @escaping (String, String) -> Void) {
        self.agentes = agentes
        alMensajeDemo = alMensaje
        demo = true
        tiempoDemo = 0
        vista?.aviso = "Modo demostración · sin modelos"
    }

    func celebrar(agentes: [AgenteConfig]) {
        self.agentes = agentes
        demo = true
        tiempoDemo = 7.6
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            self?.demo = false
            self?.vista?.aviso = nil
        }
    }

    func ocultar() {
        demo = false
        vista?.aplicar([])
        vista?.aviso = nil
    }

    private func tick() {
        guard let vista else { return }
        if demo {
            tiempoDemo += 1.0 / 60.0
            let escena = DemoGuion.escena(tiempo: tiempoDemo, agentes: agentes)
            vista.aviso = escena.aviso
            vista.aplicar(escena.cursores, instantaneo: true)
            let vistos = DemoGuion.mensajes(hasta: tiempoDemo)
            if let ultimo = vistos.last, ultimo.autor != vista.ultimoAutorDemo {
                vista.ultimoAutorDemo = ultimo.autor
                alMensajeDemo?(ultimo.autor, ultimo.texto)
            }
        } else {
            vista.avanzar(dt: 1.0 / 60.0)
        }
        ventana?.setFrame(rectanguloGlobal(), display: false)
        vista.needsDisplay = true
    }

    private func rectanguloGlobal() -> NSRect {
        NSScreen.screens.reduce(NSRect.null) { $0.union($1.frame) }
    }
}

private final class VentanaCapa: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class VistaCursores: NSView {
    var aviso: String?
    var ultimoAutorDemo = ""
    private var cursores: [CursorRender] = []

    override var isFlipped: Bool { false }

    func aplicar(_ objetivos: [CursorVisual], instantaneo: Bool = false) {
        var siguientes: [CursorRender] = []
        for objetivo in objetivos {
            var actual = cursores.first { $0.id == objetivo.id } ?? CursorRender(id: objetivo.id, x: objetivo.x, y: objetivo.y)
            actual.nombre = objetivo.nombre
            actual.color = colorHex(objetivo.colorHex)
            actual.objetivoX = objetivo.x
            actual.objetivoY = objetivo.y
            actual.burbuja = objetivo.burbuja
            actual.opacidad = objetivo.opacidad
            actual.fantasma = objetivo.fantasma
            actual.etiqueta = objetivo.etiqueta
            actual.dormido = objetivo.dormido
            if instantaneo {
                actual.x = objetivo.x
                actual.y = objetivo.y
                actual.angulo = objetivo.angulo
            }
            siguientes.append(actual)
        }
        cursores = siguientes
    }

    func avanzar(dt: Double) {
        for indice in cursores.indices {
            var estado = EstadoCursor(x: cursores[indice].x, y: cursores[indice].y, vx: cursores[indice].vx, vy: cursores[indice].vy)
            estado.avanzar(haciaX: cursores[indice].objetivoX, haciaY: cursores[indice].objetivoY, dt: dt)
            cursores[indice].x = estado.x
            cursores[indice].y = estado.y
            cursores[indice].vx = estado.vx
            cursores[indice].vy = estado.vy
            if estado.velocidad > 0.12 {
                cursores[indice].angulo = estado.anguloMovimiento
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        for cursor in cursores { dibujar(cursor) }
        if let aviso, !aviso.isEmpty { dibujarAviso(aviso) }
    }

    private func dibujar(_ cursor: CursorRender) {
        let punto = CGPoint(x: cursor.x * bounds.width, y: (1 - cursor.y) * bounds.height)
        NSGraphicsContext.saveGraphicsState()
        NSColor.black.withAlphaComponent(0.25 * cursor.opacidad).setFill()
        let sombra = NSBezierPath(ovalIn: NSRect(x: punto.x - 6, y: punto.y - 22, width: 18, height: 6))
        sombra.fill()
        let transform = NSAffineTransform()
        transform.translateX(by: punto.x, yBy: punto.y)
        transform.rotate(byRadians: -CGFloat(cursor.angulo))
        transform.concat()
        let flecha = NSBezierPath()
        flecha.move(to: .zero)
        flecha.line(to: NSPoint(x: -5.2, y: -16))
        flecha.line(to: NSPoint(x: -1.8, y: -12))
        flecha.line(to: NSPoint(x: -7.0, y: -21))
        flecha.line(to: NSPoint(x: -4.0, y: -22.2))
        flecha.line(to: NSPoint(x: 0.6, y: -13.2))
        flecha.line(to: NSPoint(x: 5.4, y: -12.4))
        flecha.close()
        NSColor.white.withAlphaComponent(cursor.opacidad).setStroke()
        (cursor.dormido ? NSColor.systemGray : cursor.color).withAlphaComponent(cursor.opacidad).setFill()
        flecha.lineWidth = 1.6
        flecha.fill()
        flecha.stroke()
        NSGraphicsContext.restoreGraphicsState()
        if cursor.fantasma { return }
        let titulo = cursor.nombre + (cursor.etiqueta.isEmpty ? "" : " · \(cursor.etiqueta)")
        let atributos: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(cursor.opacidad),
        ]
        let medida = (titulo as NSString).size(withAttributes: atributos)
        let pastilla = NSRect(x: punto.x + 14, y: punto.y - 28, width: medida.width + 14, height: medida.height + 6)
        NSColor.black.withAlphaComponent(0.55 * cursor.opacidad).setFill()
        NSBezierPath(roundedRect: pastilla, xRadius: 8, yRadius: 8).fill()
        (cursor.dormido ? NSColor.systemGray : cursor.color).withAlphaComponent(cursor.opacidad).setFill()
        NSBezierPath(roundedRect: pastilla.insetBy(dx: 1.2, dy: 1.2), xRadius: 7, yRadius: 7).fill()
        (titulo as NSString).draw(at: NSPoint(x: pastilla.minX + 7, y: pastilla.minY + 3), withAttributes: atributos)
        if let burbuja = cursor.burbuja, !burbuja.isEmpty {
            let fuente = NSFont.systemFont(ofSize: 12)
            let estilo = NSMutableParagraphStyle()
            estilo.lineBreakMode = .byWordWrapping
            let attr: [NSAttributedString.Key: Any] = [.font: fuente, .foregroundColor: NSColor.white, .paragraphStyle: estilo]
            let caja = NSRect(x: punto.x + 14, y: punto.y + 8, width: 240, height: 64)
            let alto = (burbuja as NSString).boundingRect(with: NSSize(width: 220, height: 60), options: [.usesLineFragmentOrigin], attributes: attr).height
            let fondo = NSRect(x: caja.minX, y: caja.minY, width: min(240, caja.width), height: alto + 10)
            NSColor(calibratedWhite: 0.12, alpha: 0.92 * cursor.opacidad).setFill()
            NSBezierPath(roundedRect: fondo, xRadius: 8, yRadius: 8).fill()
            (burbuja as NSString).draw(in: fondo.insetBy(dx: 8, dy: 4), withAttributes: attr)
        }
    }

    private func dibujarAviso(_ texto: String) {
        let atributos: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let medida = (texto as NSString).size(withAttributes: atributos)
        let rect = NSRect(x: (bounds.width - medida.width) / 2 - 12, y: bounds.height - 46, width: medida.width + 24, height: medida.height + 10)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        (texto as NSString).draw(at: NSPoint(x: rect.minX + 12, y: rect.minY + 5), withAttributes: atributos)
    }
}

private struct CursorRender {
    var id: String
    var nombre = ""
    var color = NSColor.white
    var x = 0.5
    var y = 0.5
    var vx = 0.0
    var vy = 0.0
    var objetivoX = 0.5
    var objetivoY = 0.5
    var angulo = -0.7
    var burbuja: String?
    var opacidad = 1.0
    var fantasma = false
    var etiqueta = ""
    var dormido = false
}

func colorHex(_ hex: String) -> NSColor {
    var limpio = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if limpio.hasPrefix("#") { limpio.removeFirst() }
    var valor: UInt64 = 0
    Scanner(string: limpio).scanHexInt64(&valor)
    guard limpio.count == 6 else { return .systemGray }
    return NSColor(srgbRed: CGFloat((valor >> 16) & 0xFF) / 255, green: CGFloat((valor >> 8) & 0xFF) / 255, blue: CGFloat(valor & 0xFF) / 255, alpha: 1)
}
#endif
