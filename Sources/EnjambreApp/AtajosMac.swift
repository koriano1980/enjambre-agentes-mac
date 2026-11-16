#if os(macOS)
import Carbon
import EnjambreNucleo

final class AtajosMac {
    static let compartido = AtajosMac()
    var alParar: (() -> Void)?
    var alOrden: (() -> Void)?
    var alVoz: (() -> Void)?
    private var instalado = false

    func instalar(interfaz: InterfazConfig) {
        if !instalado {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, evento, _ -> OSStatus in
                guard let evento else { return OSStatus(eventNotHandledErr) }
                var identificador = EventHotKeyID()
                let estado = GetEventParameter(evento, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identificador)
                if estado == noErr { AtajosMac.compartido.recibir(id: identificador.id) }
                return noErr
            }, 1, &spec, nil, nil)
            instalado = true
        }
        registrar(1, interfaz.atajoParar)
        registrar(2, interfaz.atajoOrden)
        registrar(3, interfaz.atajoVoz)
    }

    private func registrar(_ id: UInt32, _ texto: String) {
        guard let atajo = Atajo.parsear(texto), let codigo = TeclasMac.codigo(atajo.tecla) else { return }
        var mods: UInt32 = 0
        if atajo.control { mods |= TeclasMac.control }
        if atajo.opcion { mods |= TeclasMac.opcion }
        if atajo.comando { mods |= TeclasMac.comando }
        if atajo.mayusculas { mods |= TeclasMac.mayusculas }
        var ref: EventHotKeyRef?
        let hot = EventHotKeyID(signature: OSType(0x454E4A41), id: id)
        RegisterEventHotKey(codigo, mods, hot, GetApplicationEventTarget(), 0, &ref)
    }

    private func recibir(id: UInt32) {
        DispatchQueue.main.async {
            switch id {
            case 1: self.alParar?()
            case 2: self.alOrden?()
            case 3: self.alVoz?()
            default: break
            }
        }
    }
}
#endif
