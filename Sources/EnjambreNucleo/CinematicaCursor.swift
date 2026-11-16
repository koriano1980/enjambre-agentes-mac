import Foundation

public struct EstadoCursor: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double

    public init(x: Double, y: Double, vx: Double = 0, vy: Double = 0) {
        self.x = x
        self.y = y
        self.vx = vx
        self.vy = vy
    }

    /// Muelle hacia el objetivo. `dt` en segundos. El eje Y crece hacia abajo.
    public mutating func avanzar(haciaX: Double, haciaY: Double, dt: Double, rigidez: Double = 42, amortiguacion: Double = 14) {
        let paso = min(max(dt, 0), 0.05)
        let ax = (haciaX - x) * rigidez - vx * amortiguacion
        let ay = (haciaY - y) * rigidez - vy * amortiguacion
        vx += ax * paso
        vy += ay * paso
        x += vx * paso
        y += vy * paso
    }

    public var velocidad: Double { hypot(vx, vy) }

    /// 0 apunta hacia arriba. Positivo gira en el sentido del reloj (eje Y hacia abajo).
    public var anguloMovimiento: Double {
        atan2(vx, -vy)
    }
}

public func suave(_ t: Double) -> Double {
    let x = min(1, max(0, t))
    return x * x * (3 - 2 * x)
}

public func anguloDeMovimiento(dx: Double, dy: Double, minimo: Double = 0.02, reposo: Double = -0.7) -> Double {
    if hypot(dx, dy) < minimo { return reposo }
    return atan2(dx, -dy)
}
