#if os(macOS)
import EnjambreNucleo
import Network

final class SondaMac: SondaRed {
    private let monitor = NWPathMonitor()
    private let cola = DispatchQueue(label: "enjambre.red")
    private var conectada = true
    var alCambiar: ((Bool) -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] camino in
            let hay = camino.status == .satisfied
            self?.conectada = hay
            DispatchQueue.main.async { self?.alCambiar?(hay) }
        }
        monitor.start(queue: cola)
    }

    func hayInternet() async -> Bool { conectada }
}
#endif
