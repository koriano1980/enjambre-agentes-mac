#if os(macOS)
import AppKit
import EnjambreNucleo

/// Primer arranque: explica, pide consentimiento y prepara Ollama y los permisos sin abrir Terminal.
final class AsistenteMac: NSObject {
    var alTerminar: (() -> Void)?
    private var ventana: NSWindow?
    private var titulo: NSTextField?
    private var cuerpo: NSTextField?
    private var progreso: NSProgressIndicator?
    private var detalle: NSTextField?
    private var primario: NSButton?
    private var secundario: NSButton?
    private var paso = 0
    private var descargarModelos = true
    private let preset: PresetHardware
    private var trabajando = false
    private var cuentas: VentanaCuentas?

    init(gigabytes: Double) {
        preset = PresetsHardware.elegir(gigabytes: gigabytes, forzado: "auto")
        super.init()
    }

    static func yaCompletado(home: String) -> Bool {
        FileManager.default.fileExists(atPath: RutasEnjambre.soporte(home: home) + "/primer-arranque.ok")
    }

    func mostrar() {
        let ventana = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        ventana.title = "Preparar Enjambre"
        ventana.isReleasedWhenClosed = false
        let raiz = NSView()
        ventana.contentView = raiz
        let titulo = NSTextField(labelWithString: "")
        titulo.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        let cuerpo = NSTextField(wrappingLabelWithString: "")
        cuerpo.maximumNumberOfLines = 8
        let detalle = NSTextField(wrappingLabelWithString: "")
        detalle.textColor = .secondaryLabelColor
        detalle.font = NSFont.systemFont(ofSize: 12)
        let progreso = NSProgressIndicator()
        progreso.isIndeterminate = true
        progreso.style = .bar
        progreso.isHidden = true
        let primario = NSButton(title: "Continuar", target: self, action: #selector(primarioPulsado))
        primario.bezelStyle = .rounded
        primario.keyEquivalent = "\r"
        let secundario = NSButton(title: "Ahora no", target: self, action: #selector(secundarioPulsado))
        secundario.bezelStyle = .rounded
        for vista in [titulo, cuerpo, detalle, progreso, primario, secundario] as [NSView] {
            vista.translatesAutoresizingMaskIntoConstraints = false
            raiz.addSubview(vista)
        }
        NSLayoutConstraint.activate([
            titulo.topAnchor.constraint(equalTo: raiz.topAnchor, constant: 28),
            titulo.leadingAnchor.constraint(equalTo: raiz.leadingAnchor, constant: 28),
            titulo.trailingAnchor.constraint(equalTo: raiz.trailingAnchor, constant: -28),
            cuerpo.topAnchor.constraint(equalTo: titulo.bottomAnchor, constant: 12),
            cuerpo.leadingAnchor.constraint(equalTo: titulo.leadingAnchor),
            cuerpo.trailingAnchor.constraint(equalTo: titulo.trailingAnchor),
            detalle.topAnchor.constraint(equalTo: cuerpo.bottomAnchor, constant: 12),
            detalle.leadingAnchor.constraint(equalTo: titulo.leadingAnchor),
            detalle.trailingAnchor.constraint(equalTo: titulo.trailingAnchor),
            progreso.leadingAnchor.constraint(equalTo: titulo.leadingAnchor),
            progreso.trailingAnchor.constraint(equalTo: titulo.trailingAnchor),
            progreso.bottomAnchor.constraint(equalTo: primario.topAnchor, constant: -16),
            primario.trailingAnchor.constraint(equalTo: raiz.trailingAnchor, constant: -28),
            primario.bottomAnchor.constraint(equalTo: raiz.bottomAnchor, constant: -24),
            secundario.centerYAnchor.constraint(equalTo: primario.centerYAnchor),
            secundario.trailingAnchor.constraint(equalTo: primario.leadingAnchor, constant: -8),
        ])
        self.ventana = ventana
        self.titulo = titulo
        self.cuerpo = cuerpo
        self.detalle = detalle
        self.progreso = progreso
        self.primario = primario
        self.secundario = secundario
        cuentas = VentanaCuentas(home: RutasEnjambre.homeActual())
        pintar()
        ventana.center()
        ventana.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func primarioPulsado() {
        guard !trabajando else { return }
        switch paso {
        case 0, 1:
            paso += 1
            pintar()
        case 2:
            paso = 3
            pintar()
            instalarSiHaceFalta()
        case 4:
            PermisosMac.accesibilidad(pedir: true)
            PermisosMac.grabacion(pedir: true)
            PermisosMac.abrirAjustes("Accessibility")
            paso = 5
            pintar()
            cuentas?.mostrar()
        case 5:
            paso = 6
            pintar()
        default:
            marcarHecho()
            ventana?.close()
            alTerminar?()
        }
    }

    @objc private func secundarioPulsado() {
        if paso == 2 {
            descargarModelos = false
        }
        if paso >= 6 || paso == 2 {
            if paso == 2 {
                paso = 4
                pintar()
                return
            }
            marcarHecho()
            ventana?.close()
            alTerminar?()
            return
        }
        paso = min(paso + 1, 6)
        pintar()
    }

    private func pintar() {
        let modelos = Array(Set(preset.modelos.values.map(\.nombre))).sorted().joined(separator: ", ")
        switch paso {
        case 0:
            titulo?.stringValue = "Enjambre de Agentes"
            cuerpo?.stringValue = "Varios agentes trabajan en este Mac y los ves en pantalla. No hace falta la Terminal: este asistente prepara lo necesario."
            detalle?.stringValue = "Siguiente: memoria de este Mac y los modelos que caben."
            primario?.title = "Continuar"
            secundario?.title = "Omitir"
        case 1:
            titulo?.stringValue = preset.titulo
            cuerpo?.stringValue = "Detecté la memoria y elegí el preset \(preset.id). Los agentes locales comparten modelos para no llenar la RAM. Tope: \(Int(preset.presupuestoGB)) GB."
            detalle?.stringValue = "Modelos: \(modelos)."
            primario?.title = "Continuar"
            secundario?.title = "Omitir"
        case 2:
            titulo?.stringValue = "Modelos locales"
            cuerpo?.stringValue = "Con tu permiso descargo Ollama si no está, y luego los modelos del preset. Son varios gigabytes y hace falta internet solo esta vez. Sin esto el modo demo sigue funcionando, pero las órdenes locales no."
            detalle?.stringValue = "Puedes decir «Ahora no» y hacerlo más tarde desde el menú."
            primario?.title = "Descargar"
            secundario?.title = "Ahora no"
        case 3:
            titulo?.stringValue = "Preparando"
            cuerpo?.stringValue = "Instalando y descargando. Puedes dejar esta ventana abierta."
            detalle?.stringValue = ""
            primario?.isEnabled = false
        case 4:
            titulo?.stringValue = "Permisos"
            cuerpo?.stringValue = "Para mover el ratón, leer otras apps y oírte, macOS tiene que autorizar Accesibilidad, grabación de pantalla y el micrófono. El atajo de parada funciona aunque aún no concedas Accesibilidad."
            detalle?.stringValue = PermisosMac.resumen()
            primario?.title = "Abrir Ajustes"
            primario?.isEnabled = true
            secundario?.title = "Después"
        case 5:
            titulo?.stringValue = "Enlazar cuentas"
            cuerpo?.stringValue = "Abro cada servicio con tu cuenta. Si la app está instalada, uso esa. Si no, una ventana propia que recuerda la sesión en este Mac. Tú escribes la clave; yo no la veo ni la guardo."
            detalle?.stringValue = "ChatGPT, Claude, Gemini, Grok, Muse, Antigravity y Copilot. Cuando veas el chat, pulsa Comprobar o Ya entré."
            primario?.title = "Seguir"
            primario?.isEnabled = true
            secundario?.title = "Después"
            cuentas?.mostrar()
        default:
            titulo?.stringValue = "Listo"
            cuerpo?.stringValue = "El estudio ya puede abrirse. Los agentes en la nube y las apps de chat (ChatGPT, Claude, Muse, Antigravity) solo entran si hay red y tú ya iniciaste sesión en ellas."
            detalle?.stringValue = "La configuración está en Biblioteca → Application Support → Enjambre."
            primario?.title = "Abrir el estudio"
            secundario?.title = "Cerrar"
        }
    }

    private func instalarSiHaceFalta() {
        trabajando = true
        progreso?.isHidden = false
        progreso?.startAnimation(nil)
        DispatchQueue.global(qos: .userInitiated).async {
            let resultado = PreparadorLocal.preparar(preset: self.preset, descargarModelos: self.descargarModelos) { texto in
                DispatchQueue.main.async { self.detalle?.stringValue = texto }
            }
            DispatchQueue.main.async {
                self.trabajando = false
                self.progreso?.stopAnimation(nil)
                self.progreso?.isHidden = true
                self.detalle?.stringValue = resultado
                self.paso = 4
                self.pintar()
            }
        }
    }

    private func marcarHecho() {
        let carpeta = RutasEnjambre.soporte(home: RutasEnjambre.homeActual())
        try? FileManager.default.createDirectory(atPath: carpeta, withIntermediateDirectories: true)
        let marca = carpeta + "/primer-arranque.ok"
        FileManager.default.createFile(atPath: marca, contents: Data("ok".utf8))
        copiarConfiguracionSiFalta(en: carpeta)
    }

    private func copiarConfiguracionSiFalta(en carpeta: String) {
        let destino = URL(fileURLWithPath: carpeta).appendingPathComponent("enjambre.yaml")
        guard !FileManager.default.fileExists(atPath: destino.path) else { return }
        if let recurso = Bundle.main.url(forResource: "enjambre", withExtension: "yaml") {
            try? FileManager.default.copyItem(at: recurso, to: destino)
        }
        if let adaptador = Bundle.main.url(forResource: "adaptadores", withExtension: "yaml") {
            let destinoAdaptador = URL(fileURLWithPath: carpeta).appendingPathComponent("adaptadores.yaml")
            if !FileManager.default.fileExists(atPath: destinoAdaptador.path) {
                try? FileManager.default.copyItem(at: adaptador, to: destinoAdaptador)
            }
        }
    }
}

enum PreparadorLocal {
    static func preparar(preset: PresetHardware, descargarModelos: Bool, avance: (String) -> Void) -> String {
        avance("Buscando Ollama…")
        var binario = buscarOllama()
        if binario == nil {
            avance("Descargando Ollama…")
            switch instalarOllama(avance: avance) {
            case .ok(let ruta):
                binario = ruta
            case .fallo(let texto):
                return texto
            }
        }
        guard let binario else { return "No encontré Ollama. Ábrelo desde ollama.com cuando quieras y vuelve al asistente." }
        if !descargarModelos { return "Ollama está listo. Los modelos no se descargaron." }
        let nombres = Array(Set(preset.modelos.values.map(\.nombre))).sorted()
        for nombre in nombres {
            avance("Descargando \(nombre)…")
            let resultado = LanzadorProceso.ejecutar(
                ejecutable: binario,
                argumentos: ["pull", nombre],
                tiempoLimite: 60 * 45,
                vivos: ProcesosVivos()
            )
            if resultado.codigo != 0 {
                return "No pude descargar \(nombre). \(resultado.error)"
            }
        }
        return "Modelos listos: \(nombres.joined(separator: ", "))."
    }

    private static func buscarOllama() -> String? {
        let candidatos = [
            "/Applications/Ollama.app/Contents/Resources/ollama",
            NSHomeDirectory() + "/Applications/Ollama.app/Contents/Resources/ollama",
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
        ]
        return candidatos.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private enum Instalacion {
        case ok(String)
        case fallo(String)
    }

    private static func instalarOllama(avance: (String) -> Void) -> Instalacion {
        guard let url = URL(string: "https://ollama.com/download/Ollama-darwin.zip") else {
            return .fallo("La dirección de descarga de Ollama no es válida.")
        }
        let destino = FileManager.default.temporaryDirectory.appendingPathComponent("Ollama-darwin.zip")
        do {
            let datos = try Data(contentsOf: url)
            try datos.write(to: destino)
        } catch {
            return .fallo("No pude descargar Ollama. Revisa la red y vuelve a intentarlo. (\(error.localizedDescription))")
        }
        avance("Instalando Ollama…")
        let aplicaciones = FileManager.default.isWritableFile(atPath: "/Applications") ? "/Applications" : NSHomeDirectory() + "/Applications"
        try? FileManager.default.createDirectory(atPath: aplicaciones, withIntermediateDirectories: true)
        let descomprimir = LanzadorProceso.ejecutar(
            ejecutable: "/usr/bin/ditto",
            argumentos: ["-x", "-k", destino.path, aplicaciones],
            tiempoLimite: 180,
            vivos: ProcesosVivos()
        )
        if descomprimir.codigo != 0 {
            return .fallo("Descargué Ollama pero no pude instalarlo en \(aplicaciones).")
        }
        let app = aplicaciones + "/Ollama.app"
        NSWorkspace.shared.open(URL(fileURLWithPath: app))
        let binario = app + "/Contents/Resources/ollama"
        if FileManager.default.isExecutableFile(atPath: binario) { return .ok(binario) }
        return .fallo("Ollama se instaló, pero no encuentro su ejecutable. Ábrelo una vez y vuelve a este asistente.")
    }
}
#endif
