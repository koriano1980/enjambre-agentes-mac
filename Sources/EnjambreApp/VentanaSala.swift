#if os(macOS)
import AppKit
import EnjambreNucleo

final class VentanaSala: NSObject {
    var alEnviar: ((String) -> Void)?
    var alAprobar: (() -> Void)?
    var alVetar: (() -> Void)?
    private var ventana: NSWindow?
    private var texto: NSTextView?
    private var campo: NSTextField?

    func mostrar() {
        if ventana == nil { construir() }
        ventana?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func agregar(_ mensaje: MensajeSala) {
        DispatchQueue.main.async {
            if self.ventana == nil { self.construir() }
            let prefijo = mensaje.sugerencia ? "sugerencia" : mensaje.origen.rawValue
            let linea = "\(mensaje.autor) · \(prefijo)\n\(mensaje.texto)\n\n"
            self.texto?.textStorage?.append(NSAttributedString(string: linea, attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: mensaje.sugerencia ? NSColor.systemOrange : NSColor.labelColor,
            ]))
            self.texto?.scrollToEndOfDocument(nil)
        }
    }

    private func construir() {
        let ventana = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 460, height: 560), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        ventana.title = "Chat del enjambre"
        ventana.isReleasedWhenClosed = false
        let raiz = NSView()
        ventana.contentView = raiz
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let editor = NSTextView()
        editor.isEditable = false
        editor.isRichText = true
        editor.font = NSFont.systemFont(ofSize: 13)
        editor.drawsBackground = true
        editor.backgroundColor = NSColor.textBackgroundColor
        scroll.documentView = editor
        self.texto = editor
        let campo = NSTextField()
        campo.placeholderString = "Escribe, o menciona @Programador. Con un plan pendiente: aprobar o vetar."
        campo.translatesAutoresizingMaskIntoConstraints = false
        campo.target = self
        campo.action = #selector(enviar)
        self.campo = campo
        let enviar = NSButton(title: "Enviar", target: self, action: #selector(self.enviar))
        let aprobar = NSButton(title: "Aprobar", target: self, action: #selector(aprobar))
        let vetar = NSButton(title: "Vetar", target: self, action: #selector(vetar))
        for boton in [enviar, aprobar, vetar] {
            boton.bezelStyle = .rounded
            boton.translatesAutoresizingMaskIntoConstraints = false
        }
        vetar.contentTintColor = .systemRed
        let nota = NSTextField(wrappingLabelWithString: "Los mensajes de Telegram, del webhook y de las apps de chat entran como sugerencias. No se ejecutan hasta que el coordinador los incorpora y tú apruebas si hace falta.")
        nota.font = NSFont.systemFont(ofSize: 11)
        nota.textColor = .secondaryLabelColor
        nota.translatesAutoresizingMaskIntoConstraints = false
        raiz.addSubview(scroll)
        raiz.addSubview(campo)
        raiz.addSubview(enviar)
        raiz.addSubview(aprobar)
        raiz.addSubview(vetar)
        raiz.addSubview(nota)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: raiz.topAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: raiz.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: raiz.trailingAnchor, constant: -12),
            scroll.bottomAnchor.constraint(equalTo: campo.topAnchor, constant: -8),
            campo.leadingAnchor.constraint(equalTo: raiz.leadingAnchor, constant: 12),
            campo.trailingAnchor.constraint(equalTo: enviar.leadingAnchor, constant: -8),
            campo.bottomAnchor.constraint(equalTo: aprobar.topAnchor, constant: -8),
            enviar.trailingAnchor.constraint(equalTo: raiz.trailingAnchor, constant: -12),
            enviar.centerYAnchor.constraint(equalTo: campo.centerYAnchor),
            enviar.widthAnchor.constraint(equalToConstant: 80),
            aprobar.leadingAnchor.constraint(equalTo: raiz.leadingAnchor, constant: 12),
            aprobar.bottomAnchor.constraint(equalTo: nota.topAnchor, constant: -8),
            vetar.leadingAnchor.constraint(equalTo: aprobar.trailingAnchor, constant: 8),
            vetar.centerYAnchor.constraint(equalTo: aprobar.centerYAnchor),
            nota.leadingAnchor.constraint(equalTo: raiz.leadingAnchor, constant: 12),
            nota.trailingAnchor.constraint(equalTo: raiz.trailingAnchor, constant: -12),
            nota.bottomAnchor.constraint(equalTo: raiz.bottomAnchor, constant: -12),
        ])
        self.ventana = ventana
    }

    @objc private func enviar() {
        let texto = campo?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !texto.isEmpty else { return }
        campo?.stringValue = ""
        alEnviar?(texto)
    }

    @objc private func aprobar() { alAprobar?() }
    @objc private func vetar() { alVetar?() }
}
#endif
