import Foundation

public protocol SondaRed: AnyObject {
    func hayInternet() async -> Bool
}

public final class SondaFija: SondaRed {
    public var conectada: Bool
    public init(conectada: Bool) { self.conectada = conectada }
    public func hayInternet() async -> Bool { conectada }
}
