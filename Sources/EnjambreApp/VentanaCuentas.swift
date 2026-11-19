#if os(macOS)
import AppKit
import ApplicationServices
import EnjambreNucleo
import WebKit

/// Abre cada servicio con la sesión del usuario. No lee ni guarda contraseñas.
final class VentanaCuentas: NSObject, WKNavigationDelegate {
    var alCambiar: (() -> Void)?
    private var ventana: NSWindow?
    private var filas: [FilaCuenta] = []
    private var navegadores: [String: WKWebView] = [:]
    private var ventanasWeb: [String: NSWindow] = [:]
    private let archivo: URL

    init(home: String) {
        archivo = RegistroCuentas.ruta(home: home)
        super.init()
    }

    func mostrar() {
        if ventana == nil { construir() }
        refrescar()
        ventana?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func enlaces() -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: RegistroCuentas.cargar(desde: archivo).map { ($0.id, $0.enlazada) })
    }

    private func construir() {
        let ventana = NSWindow(contentRect: NSRect(x: 120, y: 80, width: 640, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        ventana.title = "Enlazar cuentas"
        ventana.isReleasedWhenClosed = false
        let raiz = NSView()
        ventana.contentView = raiz
        let nota = NSTextField(wrappingLabelWithString: "Entras tú, una vez, en tu cuenta. Enjambre no ve ni guarda la contraseña: la recuerda el navegador de la app o la aplicación si ya la tienes instalada. Si aparece un captcha, lo resuelves tú.")
        nota.font = NSFont.systemFont(ofSize: 12)
        nota.textColor = .secondaryLabelColor
        nota.translatesAutoresizingMaskIntoConstraints = false
        let pila = NSStackView()
        pila.orientation = .vertical
        pila.alignment = .leading
        pila.spacing = 8
        pila.translatesAutoresizingMaskIntoConstraints = false
        for servicio in CatalogoCuentas.servicios {
            let fila = FilaCuenta(servicio: servicio)
            fila.abrir.target = self
            fila.abrir.action = #selector(abrir(_:))
            fila.comprobar.target = self
            fila.comprobar.action = #selector(comprobar(_:))
            fila.yaEntre.target = self
            fila.yaEntre.action = #selector(yaEntre(_:))
            filas.append(fila)
            pila.addArrangedSubview(fila.vista)
            fila.vista.widthAnchor.constraint(equalTo: pila.widthAnchor).isActive = true
        }
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.documentView = pila
        raiz.addSubview(nota)
        raiz.addSubview(scroll)
        NSLayoutConstraint.activate([
            nota.topAnchor.constraint(equalTo: raiz.topAnchor, constant: 16),
            nota.leadingAnchor.constraint(equalTo: raiz.leadingAnchor, constant: 16),
            nota.trailingAnchor.constraint(equalTo: raiz.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: nota.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: raiz.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: raiz.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: raiz.bottomAnchor, constant: -16),
            pila.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -20),
        ])
        self.ventana = ventana
    }

    private func refrescar() {
        let estados = Dictionary(uniqueKeysWithValues: RegistroCuentas.cargar(desde: archivo).map { ($0.id, $0) })
        for fila in filas {
            let estado = estados[fila.servicio.id]
            if estado?.enlazada == true {
                fila.estado.stringValue = "Enlazada · \(estado?.via ?? "sesión")"
                fila.estado.textColor = .systemGreen
            } else {
                fila.estado.stringValue = "Sin enlazar"
                fila.estado.textColor = .secondaryLabelColor
            }
        }
    }

    @objc private func abrir(_ boton: NSButton) {
        guard let fila = filas.first(where: { $0.abrir === boton }) else { return }
        if let app = aplicacionInstalada(fila.servicio) {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            fila.estado.stringValue = "App abierta. Entra tú y luego pulsa Comprobar."
            return
        }
        abrirPerfil(fila.servicio)
        fila.estado.stringValue = "Ventana abierta. Entra tú. No escribo tu clave."
    }

    @objc private func comprobar(_ boton: NSButton) {
        guard let fila = filas.first(where: { $0.comprobar === boton }) else { return }
        if let web = navegadores[fila.servicio.id] {
            sondear(web, servicio: fila.servicio, manual: false)
            return
        }
        let senal = sondearApp(fila.servicio)
        aplicar(senal, servicio: fila.servicio, via: "app", manual: false)
    }

    @objc private func yaEntre(_ boton: NSButton) {
        guard let fila = filas.first(where: { $0.yaEntre === boton }) else { return }
        if let web = navegadores[fila.servicio.id] {
            sondear(web, servicio: fila.servicio, manual: true)
            return
        }
        let senal = DetectorSesion.confirmarManual(senal: sondearApp(fila.servicio))
        aplicar(senal, servicio: fila.servicio, via: "confirmada", manual: true)
    }

    private func abrirPerfil(_ servicio: ServicioCuenta) {
        if let existente = ventanasWeb[servicio.id] {
            existente.makeKeyAndOrderFront(nil)
            return
        }
        let configuracion = WKWebViewConfiguration()
        configuracion.websiteDataStore = .default()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: configuracion)
        web.navigationDelegate = self
        let ventana = NSWindow(contentRect: NSRect(x: 160, y: 80, width: 900, height: 700), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        ventana.title = "\(servicio.nombre) — tu sesión, sin guardar la clave"
        ventana.contentView = web
        ventana.isReleasedWhenClosed = false
        if let url = URL(string: servicio.url) {
            web.load(URLRequest(url: url))
        }
        ventana.makeKeyAndOrderFront(nil)
        navegadores[servicio.id] = web
        ventanasWeb[servicio.id] = ventana
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let servicio = navegadores.first(where: { $0.value === webView })?.key,
              let modelo = CatalogoCuentas.servicio(id: servicio) else { return }
        sondear(webView, servicio: modelo, manual: false)
    }

    private func sondear(_ web: WKWebView, servicio: ServicioCuenta, manual: Bool) {
        let js = """
        (() => {
          const secret = !!document.querySelector('input[type="password"]');
          const texto = ((document.body && document.body.innerText) || '').slice(0, 3000).toLowerCase();
          const captcha = texto.includes('captcha') || texto.includes('no soy un robot') || texto.includes('verify you are human') || !!document.querySelector('iframe[src*="captcha"], iframe[src*="recaptcha"], iframe[src*="hcaptcha"]');
          const composer = !!document.querySelector('textarea, [contenteditable="true"]');
          return JSON.stringify({ secret: secret, captcha: captcha, composer: composer, href: location.href });
        })()
        """
        web.evaluateJavaScript(js) { [weak self] resultado, _ in
            let datos = (resultado as? String).flatMap { $0.data(using: .utf8) }
            let json = datos.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            let senal = DetectorSesion.clasificar(
                url: json?["href"] as? String ?? web.url?.absoluteString ?? "",
                hayCampoSecreto: json?["secret"] as? Bool ?? false,
                hayCaptcha: json?["captcha"] as? Bool ?? false,
                hayComposer: json?["composer"] as? Bool ?? false
            )
            let final = manual ? DetectorSesion.confirmarManual(senal: senal) : senal
            self?.aplicar(final, servicio: servicio, via: "perfil", manual: manual)
        }
    }

    private func sondearApp(_ servicio: ServicioCuenta) -> SenalSesion {
        guard PermisosMac.accesibilidad(pedir: false), let ventana = ventanaDeApp(servicio.aplicacion) else {
            return .desconocida
        }
        var secretos = 0
        var composers = 0
        var captcha = false
        revisar(ventana, secretos: &secretos, composers: &composers, captcha: &captcha, restantes: 40)
        return DetectorSesion.clasificar(url: "", hayCampoSecreto: secretos > 0, hayCaptcha: captcha, hayComposer: composers > 0)
    }

    private func revisar(_ elemento: AXUIElement, secretos: inout Int, composers: inout Int, captcha: inout Bool, restantes: Int) {
        if restantes <= 0 { return }
        let rol = copia(elemento, kAXRoleAttribute)
        let sub = copia(elemento, kAXSubroleAttribute)
        let titulo = (copia(elemento, kAXTitleAttribute) + " " + copia(elemento, kAXDescriptionAttribute)).lowercased()
        if sub == "AXSecureTextField" || rol == "AXSecureTextField" { secretos += 1 }
        if rol == "AXTextArea" || rol == "AXTextField" { composers += 1 }
        if titulo.contains("captcha") || titulo.contains("no soy un robot") { captcha = true }
        var hijos: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elemento, kAXChildrenAttribute as CFString, &hijos) == .success,
              let lista = hijos as? [AXUIElement] else { return }
        for hijo in lista.prefix(12) {
            revisar(hijo, secretos: &secretos, composers: &composers, captcha: &captcha, restantes: restantes - 1)
        }
    }

    private func copia(_ elemento: AXUIElement, _ nombre: String) -> String {
        var valor: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elemento, nombre as CFString, &valor) == .success else { return "" }
        return valor as? String ?? ""
    }

    private func ventanaDeApp(_ nombre: String) -> AXUIElement? {
        let sistema = AXUIElementCreateSystemWide()
        var valor: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sistema, kAXFocusedApplicationAttribute as CFString, &valor) == .success else { return nil }
        let app = valor as! AXUIElement
        let titulo = copia(app, kAXTitleAttribute)
        if !titulo.isEmpty && !titulo.localizedCaseInsensitiveContains(nombre) && !nombre.localizedCaseInsensitiveContains(titulo) {
            return nil
        }
        var ventanas: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ventanas) == .success,
              let lista = ventanas as? [AXUIElement] else { return nil }
        return lista.first
    }

    private func aplicar(_ senal: SenalSesion, servicio: ServicioCuenta, via: String, manual: Bool) {
        let texto: String
        let enlazada: Bool
        switch senal {
        case .enlazada:
            texto = "Enlazada · \(via)"
            enlazada = true
        case .captcha:
            texto = "Hay un captcha. Resuélvelo tú; no lo salto."
            enlazada = false
        case .esperandoLogin:
            texto = "Sigue el inicio de sesión. No guardo la clave."
            enlazada = false
        case .desconocida:
            texto = manual ? "No pude comprobarla. Ábrela y entra hasta ver el chat." : "Aún no distingo el chat. Entra y pulsa Ya entré."
            enlazada = false
        }
        if let fila = filas.first(where: { $0.servicio.id == servicio.id }) {
            fila.estado.stringValue = texto
            fila.estado.textColor = enlazada ? .systemGreen : .secondaryLabelColor
        }
        if enlazada {
            try? RegistroCuentas.marcar(EstadoCuenta(id: servicio.id, enlazada: true, via: via, actualizado: marcaDeTiempo()), en: archivo)
            alCambiar?()
        }
    }

    private func aplicacionInstalada(_ servicio: ServicioCuenta) -> URL? {
        if !servicio.bundleID.isEmpty, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: servicio.bundleID) {
            return url
        }
        let rutas = [
            "/Applications/\(servicio.aplicacion).app",
            NSHomeDirectory() + "/Applications/\(servicio.aplicacion).app",
        ]
        return rutas.map { URL(fileURLWithPath: $0) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

private final class FilaCuenta {
    let servicio: ServicioCuenta
    let vista = NSView()
    let estado = NSTextField(labelWithString: "Sin enlazar")
    let abrir = NSButton(title: "Abrir", target: nil, action: nil)
    let comprobar = NSButton(title: "Comprobar", target: nil, action: nil)
    let yaEntre = NSButton(title: "Ya entré", target: nil, action: nil)

    init(servicio: ServicioCuenta) {
        self.servicio = servicio
        vista.translatesAutoresizingMaskIntoConstraints = false
        let nombre = NSTextField(labelWithString: servicio.nombre)
        nombre.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        for control in [nombre, estado, abrir, comprobar, yaEntre] as [NSView] {
            control.translatesAutoresizingMaskIntoConstraints = false
            vista.addSubview(control)
        }
        abrir.bezelStyle = .rounded
        comprobar.bezelStyle = .rounded
        yaEntre.bezelStyle = .rounded
        NSLayoutConstraint.activate([
            vista.heightAnchor.constraint(equalToConstant: 32),
            nombre.leadingAnchor.constraint(equalTo: vista.leadingAnchor),
            nombre.centerYAnchor.constraint(equalTo: vista.centerYAnchor),
            nombre.widthAnchor.constraint(equalToConstant: 110),
            estado.leadingAnchor.constraint(equalTo: nombre.trailingAnchor, constant: 8),
            estado.centerYAnchor.constraint(equalTo: vista.centerYAnchor),
            estado.widthAnchor.constraint(equalToConstant: 220),
            yaEntre.trailingAnchor.constraint(equalTo: vista.trailingAnchor),
            yaEntre.centerYAnchor.constraint(equalTo: vista.centerYAnchor),
            comprobar.trailingAnchor.constraint(equalTo: yaEntre.leadingAnchor, constant: -6),
            comprobar.centerYAnchor.constraint(equalTo: vista.centerYAnchor),
            abrir.trailingAnchor.constraint(equalTo: comprobar.leadingAnchor, constant: -6),
            abrir.centerYAnchor.constraint(equalTo: vista.centerYAnchor),
        ])
    }
}
#endif
