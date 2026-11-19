import Foundation

/// Servicio en el que el usuario inicia sesión él mismo. No guarda contraseñas ni cookies.
public struct ServicioCuenta: Equatable, Sendable, Identifiable {
    public var id: String
    public var nombre: String
    public var url: String
    public var aplicacion: String
    public var bundleID: String
    public var color: String

    public init(id: String, nombre: String, url: String, aplicacion: String, bundleID: String, color: String) {
        self.id = id
        self.nombre = nombre
        self.url = url
        self.aplicacion = aplicacion
        self.bundleID = bundleID
        self.color = color
    }
}

public enum SenalSesion: String, Equatable, Sendable {
    case enlazada
    case esperandoLogin
    case captcha
    case desconocida
}

public struct EstadoCuenta: Equatable, Sendable, Codable {
    public var id: String
    public var enlazada: Bool
    public var via: String
    public var actualizado: String

    public init(id: String, enlazada: Bool, via: String, actualizado: String) {
        self.id = id
        self.enlazada = enlazada
        self.via = via
        self.actualizado = actualizado
    }
}

public enum CatalogoCuentas {
    public static let servicios: [ServicioCuenta] = [
        ServicioCuenta(id: "chatgpt", nombre: "ChatGPT", url: "https://chatgpt.com", aplicacion: "ChatGPT", bundleID: "com.openai.chat", color: "#74AA9C"),
        ServicioCuenta(id: "claude", nombre: "Claude", url: "https://claude.ai", aplicacion: "Claude", bundleID: "com.anthropic.claudefordesktop", color: "#D4A27F"),
        ServicioCuenta(id: "gemini", nombre: "Gemini", url: "https://gemini.google.com", aplicacion: "Gemini", bundleID: "", color: "#8AB4F8"),
        ServicioCuenta(id: "grok", nombre: "Grok", url: "https://grok.com", aplicacion: "Grok", bundleID: "", color: "#E8E8E8"),
        ServicioCuenta(id: "muse", nombre: "Muse", url: "https://meta.ai", aplicacion: "Meta AI", bundleID: "", color: "#0668E1"),
        ServicioCuenta(id: "antigravity", nombre: "Antigravity", url: "https://antigravity.google", aplicacion: "Antigravity", bundleID: "", color: "#7CFFB2"),
        ServicioCuenta(id: "copilot", nombre: "Copilot", url: "https://copilot.microsoft.com", aplicacion: "Copilot", bundleID: "com.microsoft.copilot", color: "#A7D3F5"),
    ]

    public static func servicio(id: String) -> ServicioCuenta? {
        servicios.first { $0.id == id }
    }
}

public enum DetectorSesion {
    /// Decide solo con la dirección y con señales booleanas. Nunca recibe la contraseña ni el texto escrito.
    public static func clasificar(url: String, hayCampoSecreto: Bool, hayCaptcha: Bool, hayComposer: Bool) -> SenalSesion {
        if hayCaptcha { return .captcha }
        if hayCampoSecreto && !hayComposer { return .esperandoLogin }
        let direccion = url.lowercased()
        let pareceLogin = direccion.contains("/login")
            || direccion.contains("signin")
            || direccion.contains("sign-in")
            || direccion.contains("/auth")
            || direccion.contains("accounts.google.com")
            || direccion.contains("oauth")
        if pareceLogin && !hayComposer { return .esperandoLogin }
        if hayComposer && !hayCampoSecreto { return .enlazada }
        return .desconocida
    }

    /// El usuario dice que ya entró. No se acepta si todavía hay captcha o un campo secreto.
    public static func confirmarManual(senal: SenalSesion) -> SenalSesion {
        switch senal {
        case .captcha, .esperandoLogin:
            return senal
        case .enlazada, .desconocida:
            return .enlazada
        }
    }
}

public enum RegistroCuentas {
    public static func ruta(home: String) -> URL {
        URL(fileURLWithPath: RutasEnjambre.soporte(home: home)).appendingPathComponent("cuentas.json")
    }

    public static func cargar(desde url: URL) -> [EstadoCuenta] {
        guard let datos = try? Data(contentsOf: url),
              let lista = try? JSONDecoder().decode([EstadoCuenta].self, from: datos) else { return [] }
        return lista
    }

    public static func guardar(_ estados: [EstadoCuenta], en url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let datos = try JSONEncoder().encode(estados)
        try datos.write(to: url, options: .atomic)
    }

    public static func marcar(_ estado: EstadoCuenta, en url: URL) throws {
        var actuales = cargar(desde: url).filter { $0.id != estado.id }
        actuales.append(estado)
        actuales.sort { $0.id < $1.id }
        try guardar(actuales, en: url)
    }

    public static func enlazadas(en url: URL) -> Set<String> {
        Set(cargar(desde: url).filter(\.enlazada).map(\.id))
    }
}
