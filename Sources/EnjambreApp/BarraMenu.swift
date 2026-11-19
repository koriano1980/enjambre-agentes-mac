#if os(macOS)
import AppKit
import EnjambreNucleo

final class BarraMenu: NSObject {
    var alEjecutar: ((String) -> Void)?
    var alHablar: (() -> Void)?
    var alDemo: (() -> Void)?
    var alParar: (() -> Void)?
    var alSala: (() -> Void)?
    var alPermisos: (() -> Void)?
    var alRegistro: (() -> Void)?
    var alCuentas: (() -> Void)?
    private var item: NSStatusItem?
    private var popover: NSPopover?
    private var campo: NSTextField?
    private var resultado: NSTextField?
    private var estados: NSTextField?

    func instalar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = icono()
        item.button?.imagePosition = .imageLeading
        item.button?.title = " Enjambre"
        item.button?.target = self
        item.button?.action = #selector(pulsar)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.item = item
    }

    func marcarOcupado(_ ocupado: Bool) {
        item?.button?.title = ocupado ? " Parar" : " Enjambre"
    }

    func fijarResultado(_ texto: String) {
        resultado?.stringValue = texto
    }

    func fijarEstados(_ texto: String) {
        estados?.stringValue = texto
    }

    func fijarCampo(_ texto: String) {
        campo?.stringValue = texto
    }

    func mostrar() {
        construirSiHaceFalta()
        guard let boton = item?.button, let popover else { return }
        if popover.isShown { popover.performClose(nil); return }
        popover.show(relativeTo: boton.bounds, of: boton, preferredEdge: .minY)
        campo?.becomeFirstResponder()
    }

    @objc private func pulsar() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Parar todo", action: #selector(parar), keyEquivalent: "")
            menu.addItem(withTitle: "Chat del enjambre", action: #selector(sala), keyEquivalent: "")
            menu.addItem(withTitle: "Modo demostración", action: #selector(demo), keyEquivalent: "")
            menu.addItem(withTitle: "Enlazar cuentas…", action: #selector(cuentas), keyEquivalent: "")
            menu.addItem(withTitle: "Permisos…", action: #selector(permisos), keyEquivalent: "")
            menu.addItem(withTitle: "Registro…", action: #selector(registro), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Salir", action: #selector(salir), keyEquivalent: "q")
            menu.items.forEach { $0.target = self }
            item?.menu = menu
            item?.button?.performClick(nil)
            item?.menu = nil
            return
        }
        mostrar()
    }

    private func construirSiHaceFalta() {
        guard popover == nil else { return }
        let vista = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 360))
        let titulo = NSTextField(labelWithString: "Enjambre de Agentes")
        titulo.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        let campo = NSTextField()
        campo.placeholderString = "Orden en español"
        campo.target = self
        campo.action = #selector(ejecutar)
        self.campo = campo
        let ejecutar = NSButton(title: "Ejecutar", target: self, action: #selector(self.ejecutar))
        let hablar = NSButton(title: "Hablar", target: self, action: #selector(self.hablar))
        let parar = NSButton(title: "Parar todo  ⌃⌥⌘K", target: self, action: #selector(self.parar))
        parar.contentTintColor = .systemRed
        let chat = NSButton(title: "Chat", target: self, action: #selector(sala))
        let demo = NSButton(title: "Demo", target: self, action: #selector(self.demo))
        let estados = NSTextField(wrappingLabelWithString: "Los agentes aparecen cuando hay una orden.")
        estados.maximumNumberOfLines = 6
        self.estados = estados
        let resultado = NSTextField(wrappingLabelWithString: "")
        resultado.maximumNumberOfLines = 5
        self.resultado = resultado
        let pie = NSTextField(labelWithString: "⌃⌥⌘E orden · ⌃⌥⌘Espacio voz · ⌃⌥⌘K parar")
        pie.textColor = .secondaryLabelColor
        pie.font = NSFont.systemFont(ofSize: 11)
        let piezas = [titulo, campo, ejecutar, hablar, parar, chat, demo, estados, resultado, pie]
        for pieza in piezas {
            pieza.translatesAutoresizingMaskIntoConstraints = false
            vista.addSubview(pieza)
        }
        NSLayoutConstraint.activate([
            titulo.topAnchor.constraint(equalTo: vista.topAnchor, constant: 14),
            titulo.leadingAnchor.constraint(equalTo: vista.leadingAnchor, constant: 14),
            campo.topAnchor.constraint(equalTo: titulo.bottomAnchor, constant: 10),
            campo.leadingAnchor.constraint(equalTo: vista.leadingAnchor, constant: 14),
            campo.trailingAnchor.constraint(equalTo: vista.trailingAnchor, constant: -14),
            ejecutar.topAnchor.constraint(equalTo: campo.bottomAnchor, constant: 8),
            ejecutar.leadingAnchor.constraint(equalTo: vista.leadingAnchor, constant: 14),
            hablar.centerYAnchor.constraint(equalTo: ejecutar.centerYAnchor),
            hablar.leadingAnchor.constraint(equalTo: ejecutar.trailingAnchor, constant: 8),
            demo.centerYAnchor.constraint(equalTo: ejecutar.centerYAnchor),
            demo.leadingAnchor.constraint(equalTo: hablar.trailingAnchor, constant: 8),
            chat.centerYAnchor.constraint(equalTo: ejecutar.centerYAnchor),
            chat.leadingAnchor.constraint(equalTo: demo.trailingAnchor, constant: 8),
            parar.topAnchor.constraint(equalTo: ejecutar.bottomAnchor, constant: 8),
            parar.leadingAnchor.constraint(equalTo: vista.leadingAnchor, constant: 14),
            parar.trailingAnchor.constraint(equalTo: vista.trailingAnchor, constant: -14),
            estados.topAnchor.constraint(equalTo: parar.bottomAnchor, constant: 10),
            estados.leadingAnchor.constraint(equalTo: vista.leadingAnchor, constant: 14),
            estados.trailingAnchor.constraint(equalTo: vista.trailingAnchor, constant: -14),
            resultado.topAnchor.constraint(equalTo: estados.bottomAnchor, constant: 8),
            resultado.leadingAnchor.constraint(equalTo: vista.leadingAnchor, constant: 14),
            resultado.trailingAnchor.constraint(equalTo: vista.trailingAnchor, constant: -14),
            pie.leadingAnchor.constraint(equalTo: vista.leadingAnchor, constant: 14),
            pie.bottomAnchor.constraint(equalTo: vista.bottomAnchor, constant: -12),
        ])
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 360)
        let controlador = NSViewController()
        controlador.view = vista
        popover.contentViewController = controlador
        self.popover = popover
    }

    @objc private func ejecutar() { alEjecutar?(campo?.stringValue ?? "") }
    @objc private func hablar() { alHablar?() }
    @objc private func demo() { alDemo?() }
    @objc private func parar() { alParar?() }
    @objc private func sala() { alSala?() }
    @objc private func permisos() { alPermisos?() }
    @objc private func cuentas() { alCuentas?() }
    @objc private func registro() { alRegistro?() }
    @objc private func salir() { NSApp.terminate(nil) }

    private func icono() -> NSImage {
        let imagen = NSImage(size: NSSize(width: 18, height: 18))
        imagen.lockFocus()
        NSColor.labelColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 2, y: 8, width: 4, height: 4)).fill()
        NSBezierPath(ovalIn: NSRect(x: 7, y: 4, width: 4, height: 4)).fill()
        NSBezierPath(ovalIn: NSRect(x: 12, y: 9, width: 4, height: 4)).fill()
        imagen.unlockFocus()
        imagen.isTemplate = true
        return imagen
    }
}
#endif
