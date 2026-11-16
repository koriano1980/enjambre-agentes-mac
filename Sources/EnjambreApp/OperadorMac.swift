#if os(macOS)
import AppKit
import ApplicationServices
import CoreGraphics
import EnjambreNucleo
import Vision

actor CandadoInterfaz {
    private var raton = false
    private var apps: Set<String> = []
    private var espera: [CheckedContinuation<Void, Never>] = []

    func conApp<T>(_ id: String, raton quiereRaton: Bool, _ cuerpo: () async throws -> T) async rethrows -> T {
        await adquirir(id, raton: quiereRaton)
        do {
            let valor = try await cuerpo()
            liberar(id, raton: quiereRaton)
            return valor
        } catch {
            liberar(id, raton: quiereRaton)
            throw error
        }
    }

    private func adquirir(_ id: String, raton quiereRaton: Bool) async {
        while apps.contains(id) || (quiereRaton && raton) {
            await withCheckedContinuation { espera.append($0) }
        }
        apps.insert(id)
        if quiereRaton { raton = true }
    }

    private func liberar(_ id: String, raton quiereRaton: Bool) {
        apps.remove(id)
        if quiereRaton { raton = false }
        let pendientes = espera
        espera.removeAll()
        for continuacion in pendientes { continuacion.resume() }
    }
}

final class OperadorMac: OperadorChat {
    let candado = CandadoInterfaz()
    var alCursor: ((PuntoNorm, String) -> Void)?

    func moverRaton(x: Double, y: Double, normalizado: Bool, accion: String) async -> String {
        await candado.conApp("raton", raton: true) {
            let punto = self.absoluto(x: x, y: y, normalizado: normalizado)
            let mover = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: punto, mouseButton: .left)
            mover?.post(tap: .cghidEventTap)
            if accion == "clic" || accion == "doble" || accion == "derecho" {
                let boton: CGMouseButton = accion == "derecho" ? .right : .left
                let abajo: CGEventType = boton == .right ? .rightMouseDown : .leftMouseDown
                let arriba: CGEventType = boton == .right ? .rightMouseUp : .leftMouseUp
                let veces = accion == "doble" ? 2 : 1
                for indice in 1...veces {
                    let pulsacion = CGEvent(mouseEventSource: nil, mouseType: abajo, mouseCursorPosition: punto, mouseButton: boton)
                    pulsacion?.setIntegerValueField(.mouseEventClickState, value: Int64(indice))
                    pulsacion?.post(tap: .cghidEventTap)
                    let suelta = CGEvent(mouseEventSource: nil, mouseType: arriba, mouseCursorPosition: punto, mouseButton: boton)
                    suelta?.setIntegerValueField(.mouseEventClickState, value: Int64(indice))
                    suelta?.post(tap: .cghidEventTap)
                }
            }
            return "Ratón en \(Int(punto.x)), \(Int(punto.y)) (\(accion))."
        }
    }

    func escribirTeclado(_ texto: String) async -> String {
        await candado.conApp("teclado", raton: true) {
            for caracter in texto {
                let unidades = Array(String(caracter).utf16)
                let abajo = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
                let arriba = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
                unidades.withUnsafeBufferPointer { buffer in
                    guard let base = buffer.baseAddress else { return }
                    abajo?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                    arriba?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                }
                abajo?.post(tap: .cghidEventTap)
                arriba?.post(tap: .cghidEventTap)
            }
            return "Escribí \(texto.count) caracteres con el teclado real, en cola."
        }
    }

    private func absoluto(x: Double, y: Double, normalizado: Bool) -> CGPoint {
        let pantalla = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        let ancho = pantalla?.frame.width ?? 1
        let alto = pantalla?.frame.height ?? 1
        if normalizado { return CGPoint(x: x * ancho, y: y * alto) }
        return CGPoint(x: x, y: y)
    }

    func preguntar(adaptador: AdaptadorChat, texto: String, alMover: @escaping @Sendable (PuntoNorm) -> Void) async -> String {
        let bajo = texto.lowercased()
        if bajo.contains("captcha") || bajo.contains("no soy un robot") {
            return "No voy a intentar saltarme un captcha. Resuélvelo tú y vuelve a pedir la orden."
        }
        return await (try? candado.conApp(adaptador.id, raton: false) {
            await self.operar(adaptador, texto: texto, alMover: alMover)
        }) ?? "No pude operar \(adaptador.nombre)."
    }

    private func operar(_ adaptador: AdaptadorChat, texto: String, alMover: @escaping (PuntoNorm) -> Void) async -> String {
        if !PermisosMac.accesibilidad(pedir: true) {
            return "Falta el permiso de Accesibilidad para manejar \(adaptador.nombre)."
        }
        if adaptador.tipo == "web" || !adaptador.url.isEmpty {
            let destino = adaptador.url.isEmpty ? adaptador.aplicacion : adaptador.url
            if destino.hasPrefix("http") {
                NSWorkspace.shared.open(URL(string: destino)!)
            }
        }
        if adaptador.tipo == "app" {
            NSWorkspace.shared.openApplication(at: urlAplicacion(adaptador.aplicacion), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard let ventana = elementoVentana(nombre: adaptador.aplicacion) ?? elementoVentana(nombre: adaptador.navegador) else {
            return "No encuentro la ventana de \(adaptador.nombre). Ábrela e inicia sesión tú mismo."
        }
        guard let campo = buscar(ventana, rol: adaptador.rolEntrada, pista: adaptador.pistaEntrada, profundidad: 0, restantes: 80) else {
            return "No encuentro el campo de texto de \(adaptador.nombre). Ajusta rol_entrada en adaptadores.yaml."
        }
        if esCampoSecreto(campo) {
            return "Eso parece un campo de contraseña. Inicia sesión tú; yo no escribo claves."
        }
        if let punto = puntoDe(campo) {
            let normal = normalizar(punto)
            alMover(normal)
            alCursor?(normal, adaptador.nombre)
        }
        let antes = leerTextos(ventana, rol: adaptador.rolRespuesta)
        AXUIElementSetAttributeValue(campo, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(campo, kAXValueAttribute as CFString, texto as CFString)
        if !adaptador.teclaEnviar.isEmpty {
            await candado.conApp(adaptador.id + "-tecla", raton: true) {
                pulsar(adaptador.teclaEnviar)
            }
        }
        let limite = Date().addingTimeInterval(adaptador.esperaSegundos)
        var ultimo = ""
        var estable = 0
        while Date() < limite {
            try? await Task.sleep(nanoseconds: 700_000_000)
            let ahora = leerTextos(ventana, rol: adaptador.rolRespuesta)
            let nuevo = ahora.replacingOccurrences(of: antes, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if nuevo.lowercased().contains("captcha") || nuevo.lowercased().contains("verify you are human") || nuevo.lowercased().contains("no soy un robot") {
                return "Hay un captcha en \(adaptador.nombre). Resuélvelo tú; no lo voy a saltar."
            }
            if !nuevo.isEmpty, nuevo == ultimo { estable += 1 } else { estable = 0 }
            ultimo = nuevo
            if estable >= 2, !nuevo.isEmpty { return String(nuevo.suffix(4000)) }
        }
        if !ultimo.isEmpty { return String(ultimo.suffix(4000)) }
        if let ocr = reconocerPantalla(dueno: adaptador.aplicacion), !ocr.isEmpty {
            return "Leído por OCR:\n" + String(ocr.suffix(3000))
        }
        return "\(adaptador.nombre) no mostró una respuesta legible. Si hace falta iniciar sesión, hazlo tú."
    }

    private func urlAplicacion(_ nombre: String) -> URL {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: nombre)
            ?? URL(fileURLWithPath: "/Applications/\(nombre).app")
    }

    private func elementoVentana(nombre: String) -> AXUIElement? {
        let sistema = AXUIElementCreateSystemWide()
        var valor: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sistema, kAXFocusedApplicationAttribute as CFString, &valor) == .success else { return nil }
        let app = valor as! AXUIElement
        var nombreApp: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXTitleAttribute as CFString, &nombreApp)
        let titulo = nombreApp as? String ?? ""
        if !titulo.isEmpty, !titulo.localizedCaseInsensitiveContains(nombre), !nombre.localizedCaseInsensitiveContains(titulo) {
            // Seguimos con la app al frente: el usuario puede haberla dejado activa.
        }
        var ventanas: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ventanas) == .success,
              let lista = ventanas as? [AXUIElement], let primera = lista.first else { return nil }
        return primera
    }

    private func buscar(_ elemento: AXUIElement, rol buscado: String, pista: String, profundidad: Int, restantes: inout Int) -> AXUIElement? {
        if restantes <= 0 || profundidad > 7 { return nil }
        restantes -= 1
        let rol = atributo(elemento, kAXRoleAttribute)
        let titulo = (atributo(elemento, kAXTitleAttribute) + " " + atributo(elemento, kAXDescriptionAttribute) + " " + atributo(elemento, "AXPlaceholderValue")).lowercased()
        let pistaBaja = pista.lowercased()
        if rol == buscado, pistaBaja.isEmpty || titulo.contains(pistaBaja) { return elemento }
        var hijos: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elemento, kAXChildrenAttribute as CFString, &hijos) == .success,
              let lista = hijos as? [AXUIElement] else { return nil }
        for hijo in lista.prefix(20) {
            if let hallado = buscar(hijo, rol: buscado, pista: pista, profundidad: profundidad + 1, restantes: &restantes) {
                return hallado
            }
        }
        return nil
    }

    private func esCampoSecreto(_ elemento: AXUIElement) -> Bool {
        atributo(elemento, kAXSubroleAttribute) == "AXSecureTextField"
    }

    private func atributo(_ elemento: AXUIElement, _ nombre: String) -> String {
        var valor: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elemento, nombre as CFString, &valor) == .success else { return "" }
        return valor as? String ?? ""
    }

    private func puntoDe(_ elemento: AXUIElement) -> CGPoint? {
        var valor: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elemento, kAXPositionAttribute as CFString, &valor) == .success else { return nil }
        let ax = valor as! AXValue
        var punto = CGPoint.zero
        guard AXValueGetValue(ax, .cgPoint, &punto) else { return nil }
        return punto
    }

    private func normalizar(_ punto: CGPoint) -> PuntoNorm {
        let pantalla = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        let ancho = pantalla?.frame.width ?? 1
        let alto = pantalla?.frame.height ?? 1
        return PuntoNorm(x: min(0.98, max(0.02, punto.x / ancho)), y: min(0.98, max(0.02, punto.y / alto)))
    }

    private func leerTextos(_ raiz: AXUIElement, rol: String) -> String {
        var restantes = 60
        var trozos: [String] = []
        recolectar(raiz, rol: rol, trozos: &trozos, restantes: &restantes, profundidad: 0)
        return trozos.joined(separator: "\n")
    }

    private func recolectar(_ elemento: AXUIElement, rol: String, trozos: inout [String], restantes: inout Int, profundidad: Int) {
        if restantes <= 0 || profundidad > 6 { return }
        restantes -= 1
        if atributo(elemento, kAXRoleAttribute) == rol || atributo(elemento, kAXRoleAttribute) == "AXTextArea" {
            let valor = atributo(elemento, kAXValueAttribute)
            let titulo = atributo(elemento, kAXTitleAttribute)
            if !valor.isEmpty { trozos.append(valor) }
            else if !titulo.isEmpty { trozos.append(titulo) }
        }
        var hijos: CFTypeRef?
        guard AXUIElementCopyAttributeValue(elemento, kAXChildrenAttribute as CFString, &hijos) == .success,
              let lista = hijos as? [AXUIElement] else { return }
        for hijo in lista.prefix(16) {
            recolectar(hijo, rol: rol, trozos: &trozos, restantes: &restantes, profundidad: profundidad + 1)
        }
    }

    private func pulsar(_ tecla: String) {
        guard let codigo = TeclasMac.codigo(tecla == "return" ? "return" : tecla) else { return }
        let origen = CGEventSource(stateID: .hidSystemState)
        let abajo = CGEvent(keyboardEventSource: origen, virtualKey: CGKeyCode(codigo), keyDown: true)
        let arriba = CGEvent(keyboardEventSource: origen, virtualKey: CGKeyCode(codigo), keyDown: false)
        abajo?.post(tap: .cghidEventTap)
        arriba?.post(tap: .cghidEventTap)
    }

    private func reconocerPantalla(dueno: String) -> String? {
        guard PermisosMac.grabacion(pedir: true) else { return nil }
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        guard let ventana = info.first(where: { ($0[kCGWindowOwnerName as String] as? String)?.localizedCaseInsensitiveContains(dueno) == true }),
              let numero = ventana[kCGWindowNumber as String] as? CGWindowID else { return nil }
        guard let imagen = CGWindowListCreateImage(.null, .optionIncludingWindow, numero, [.boundsIgnoreFraming, .bestResolution]) else { return nil }
        let peticion = VNRecognizeTextRequest()
        peticion.recognitionLanguages = ["es-ES", "en-US"]
        peticion.recognitionLevel = .accurate
        let manejador = VNImageRequestHandler(cgImage: imagen, options: [:])
        try? manejador.perform([peticion])
        return peticion.results?.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

#endif
