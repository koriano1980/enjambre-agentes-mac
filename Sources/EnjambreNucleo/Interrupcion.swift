import Foundation

/// Bandera de parada. Cada orden usa la suya: el interruptor mata la actual y la siguiente nace limpia.
public actor Interrupcion {
    private var detenido = false
    private let vivos: ProcesosVivos

    public init(vivos: ProcesosVivos = .compartido) {
        self.vivos = vivos
    }

    public func parar() {
        detenido = true
        vivos.matarTodos()
    }

    public func reanudar() {
        detenido = false
    }

    public func estaDetenido() -> Bool {
        detenido
    }

    public var procesos: ProcesosVivos { vivos }
}
