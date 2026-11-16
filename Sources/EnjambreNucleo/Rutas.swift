import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public enum RutasEnjambre {
    public static func homeActual() -> String {
        NSHomeDirectory()
    }

    public static func expandir(_ ruta: String, home: String) -> String {
        if ruta == "~" { return home }
        if ruta.hasPrefix("~/") { return home + ruta.dropFirst(1) }
        if ruta == "$HOME" { return home }
        if ruta.hasPrefix("$HOME/") { return home + ruta.dropFirst(5) }
        if ruta.hasPrefix("${HOME}") { return home + ruta.dropFirst(7) }
        return ruta
    }

    public static func canonica(_ ruta: String, home: String, directorio: String) -> String {
        var texto = expandir(ruta, home: home)
        if texto.hasPrefix("~") {
            texto = expandir(texto, home: home)
        }
        if !texto.hasPrefix("/") {
            let base = expandir(directorio, home: home)
            texto = URL(fileURLWithPath: base).appendingPathComponent(texto).path
        }
        return URL(fileURLWithPath: texto).standardizedFileURL.path
    }

    public static func estaDentro(_ ruta: String, de raiz: String) -> Bool {
        let archivo = URL(fileURLWithPath: ruta).standardizedFileURL.path
        let base = URL(fileURLWithPath: raiz).standardizedFileURL.path
        if archivo == base { return true }
        let prefijo = base.hasSuffix("/") ? base : base + "/"
        return archivo.hasPrefix(prefijo)
    }

    public static func soporte(home: String) -> String {
        expandir("~/Library/Application Support/Enjambre", home: home)
    }

    public static func registro(home: String) -> String {
        expandir("~/Library/Logs/Enjambre/acciones.jsonl", home: home)
    }

    public static func pid(home: String) -> String {
        soporte(home: home) + "/enjambre.pid"
    }

    public static func socket(home: String) -> String {
        let preferida = soporte(home: home) + "/control.sock"
        if preferida.utf8.count < 100 { return preferida }
        return "/tmp/enjambre-\(getuid()).sock"
    }

    /// Orden: argumento, variable ENJAMBRE_CONFIG, ./config/enjambre.yaml, soporte, nil si no hay archivo.
    public static func buscarConfiguracion(explicita: String?, directorio: String, home: String, existe: (String) -> Bool) -> String? {
        if let explicita, !explicita.isEmpty {
            return canonica(explicita, home: home, directorio: directorio)
        }
        if let entorno = ProcessInfo.processInfo.environment["ENJAMBRE_CONFIG"], !entorno.isEmpty {
            return canonica(entorno, home: home, directorio: directorio)
        }
        let localYAML = URL(fileURLWithPath: directorio).appendingPathComponent("config/enjambre.yaml").path
        if existe(localYAML) { return localYAML }
        let localJSON = URL(fileURLWithPath: directorio).appendingPathComponent("config/enjambre.json").path
        if existe(localJSON) { return localJSON }
        let soporteYAML = soporte(home: home) + "/enjambre.yaml"
        if existe(soporteYAML) { return soporteYAML }
        let soporteJSON = soporte(home: home) + "/enjambre.json"
        if existe(soporteJSON) { return soporteJSON }
        return nil
    }
}

public enum Redaccion {
    public static func limpiar(_ texto: String) -> String {
        var salida = texto
        let patrones = [
            #"bot\d+:[A-Za-z0-9_-]{8,}"#,
            #"sk-ant-[A-Za-z0-9_-]{8,}"#,
            #"sk-[A-Za-z0-9_-]{16,}"#,
            #"Bearer\s+[A-Za-z0-9._\-]{8,}"#,
        ]
        for patron in patrones {
            guard let regex = try? NSRegularExpression(pattern: patron, options: []) else { continue }
            let rango = NSRange(salida.startIndex..., in: salida)
            salida = regex.stringByReplacingMatches(in: salida, options: [], range: rango, withTemplate: "•••")
        }
        return salida
    }
}
