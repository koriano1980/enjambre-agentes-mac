#if os(macOS)
import AppKit
import EnjambreNucleo

final class ConfirmadorMac: Confirmador {
    func confirmar(_ solicitud: SolicitudConfirmacion) async -> Bool {
        await withCheckedContinuation { continuacion in
            DispatchQueue.main.async {
                let alerta = NSAlert()
                alerta.messageText = "Confirmar acción"
                alerta.informativeText = "\(solicitud.agente) quiere \(solicitud.motivo).\n\n\(solicitud.detalle)\n\nSi no respondes, se deniega."
                alerta.alertStyle = .warning
                alerta.addButton(withTitle: "Denegar")
                alerta.addButton(withTitle: "Permitir")
                NSApp.activate(ignoringOtherApps: true)
                let cierre = DispatchWorkItem { NSApp.abortModal() }
                DispatchQueue.main.asyncAfter(deadline: .now() + solicitud.tiempoSegundos, execute: cierre)
                let respuesta = alerta.runModal()
                cierre.cancel()
                continuacion.resume(returning: respuesta == .alertSecondButtonReturn)
            }
        }
    }
}
#endif
