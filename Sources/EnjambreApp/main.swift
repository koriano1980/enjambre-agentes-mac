import EnjambreNucleo
import Foundation

#if os(macOS)
let modo = interpretarArgumentos(CommandLine.arguments)
if abrirInterfaz(modo) {
    ArranqueMac.principal(modo: modo)
} else {
    Task {
        let codigo = await CLINucleo.ejecutar(modo)
        exit(codigo)
    }
    dispatchMain()
}
#else
let codigo = await CLINucleo.ejecutar(interpretarArgumentos(CommandLine.arguments))
exit(codigo)
#endif

#if os(macOS)
private func abrirInterfaz(_ modo: ModoArranque) -> Bool {
    switch modo {
    case .interfaz:
        return true
    case .demo(_, _, let sinVentana, _):
        return !sinVentana
    default:
        return false
    }
}
#endif
