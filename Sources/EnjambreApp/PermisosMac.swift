#if os(macOS)
import AppKit
import ApplicationServices
import CoreGraphics

enum PermisosMac {
    static func accesibilidad(pedir: Bool) -> Bool {
        if pedir {
            let clave = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            let opciones = [clave: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(opciones)
        }
        return AXIsProcessTrusted()
    }

    static func grabacion(pedir: Bool) -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        if pedir { return CGRequestScreenCaptureAccess() }
        return false
    }

    static func resumen() -> String {
        let ax = accesibilidad(pedir: false) ? "concedida" : "pendiente"
        let pantalla = grabacion(pedir: false) ? "concedida" : "pendiente"
        return "Accesibilidad: \(ax). Grabación de pantalla: \(pantalla). El micrófono y la voz se piden al pulsar Hablar. La primera vez que un agente controle otra app, macOS pedirá automatización."
    }

    static func abrirAjustes(_ ancla: String) {
        let modernos = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_\(ancla)",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_\(ancla)",
        ]
        for texto in modernos {
            if let url = URL(string: texto), NSWorkspace.shared.open(url) { return }
        }
    }
}
#endif
