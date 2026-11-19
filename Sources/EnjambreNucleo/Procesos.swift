import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct ResultadoProceso: Equatable, Sendable {
    public var codigo: Int32
    public var salida: String
    public var error: String
    public var excedioTiempo: Bool
    public var detenido: Bool

    public init(codigo: Int32, salida: String, error: String, excedioTiempo: Bool = false, detenido: Bool = false) {
        self.codigo = codigo
        self.salida = salida
        self.error = error
        self.excedioTiempo = excedioTiempo
        self.detenido = detenido
    }
}

public final class ProcesosVivos: @unchecked Sendable {
    public static let compartido = ProcesosVivos()
    private let lock = NSLock()
    private var grupos: [Int32: Bool] = [:]

    public init() {}

    public func registrar(pid: Int32, grupoPropio: Bool) {
        guard pid > 0 else { return }
        lock.lock()
        grupos[pid] = grupoPropio
        lock.unlock()
    }

    public func olvidar(pid: Int32) {
        lock.lock()
        grupos[pid] = nil
        lock.unlock()
    }

    public func matarTodos() {
        lock.lock()
        let copia = grupos
        grupos.removeAll()
        lock.unlock()
        for (pid, grupo) in copia {
            matar(pid: pid, grupoPropio: grupo)
        }
    }

    public var cantidad: Int {
        lock.lock()
        defer { lock.unlock() }
        return grupos.count
    }
}

public func matar(pid: Int32, grupoPropio: Bool) {
    guard pid > 1 else { return }
    if grupoPropio {
        _ = kill(-pid, SIGKILL)
    }
    _ = kill(pid, SIGKILL)
}

public enum LanzadorProceso {
    public static func ejecutar(
        ejecutable: String,
        argumentos: [String],
        directorio: String? = nil,
        entrada: String? = nil,
        entorno: [String: String]? = nil,
        tiempoLimite: TimeInterval,
        vivos: ProcesosVivos
    ) -> ResultadoProceso {
        let proceso = Process()
        proceso.executableURL = URL(fileURLWithPath: ejecutable)
        proceso.arguments = argumentos
        if let directorio, !directorio.isEmpty {
            proceso.currentDirectoryURL = URL(fileURLWithPath: directorio)
        }
        if let entorno {
            proceso.environment = entorno
        }
        let salidaPipe = Pipe()
        let errorPipe = Pipe()
        let entradaPipe = Pipe()
        proceso.standardOutput = salidaPipe
        proceso.standardError = errorPipe
        proceso.standardInput = entradaPipe

        do {
            try proceso.run()
        } catch {
            return ResultadoProceso(codigo: 127, salida: "", error: "No se pudo ejecutar \(ejecutable): \(error.localizedDescription)", excedioTiempo: false, detenido: false)
        }

        let pid = proceso.processIdentifier
        let grupoPropio = setpgid(pid, pid) == 0
        vivos.registrar(pid: pid, grupoPropio: grupoPropio)
        defer { vivos.olvidar(pid: pid) }

        let grupoLectura = DispatchGroup()
        let datosSalida = AcumuladorDatos()
        let datosError = AcumuladorDatos()

        grupoLectura.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            datosSalida.agregar(salidaPipe.fileHandleForReading.readDataToEndOfFile())
            grupoLectura.leave()
        }
        grupoLectura.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            datosError.agregar(errorPipe.fileHandleForReading.readDataToEndOfFile())
            grupoLectura.leave()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            if let entrada, let datos = entrada.data(using: .utf8) {
                try? entradaPipe.fileHandleForWriting.write(contentsOf: datos)
            }
            try? entradaPipe.fileHandleForWriting.close()
        }

        let limite = max(0.05, tiempoLimite)
        let inicio = Date()
        var excedio = false
        var detenido = false
        while proceso.isRunning {
            if vivos.estaVivo(pid) == false {
                detenido = true
                matar(pid: pid, grupoPropio: grupoPropio)
                break
            }
            if Date().timeIntervalSince(inicio) > limite {
                excedio = true
                matar(pid: pid, grupoPropio: grupoPropio)
                break
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        proceso.waitUntilExit()
        _ = grupoLectura.wait(timeout: .now() + 2)

        let salida = datosSalida.texto()
        let error = datosError.texto()
        let codigo = proceso.terminationStatus
        return ResultadoProceso(
            codigo: detenido || excedio ? max(codigo, 1) : codigo,
            salida: salida,
            error: error,
            excedioTiempo: excedio,
            detenido: detenido
        )
    }
}

private final class AcumuladorDatos: @unchecked Sendable {
    private let lock = NSLock()
    private var datos = Data()

    func agregar(_ trozo: Data) {
        lock.lock()
        datos.append(trozo)
        lock.unlock()
    }

    func texto() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: datos, encoding: .utf8) ?? ""
    }
}

extension ProcesosVivos {
    fileprivate func estaVivo(_ pid: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return grupos[pid] != nil
    }
}

public func entornoConRutasHabituales(home: String) -> [String: String] {
    var entorno = ProcessInfo.processInfo.environment
    let extra = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:\(home)/bin"
    if let path = entorno["PATH"], !path.isEmpty {
        entorno["PATH"] = extra + ":" + path
    } else {
        entorno["PATH"] = extra + ":/usr/bin:/bin:/usr/sbin:/sbin"
    }
    return entorno
}

public func shellDelSistema() -> String {
    #if os(macOS)
    return "/bin/zsh"
    #else
    return "/bin/bash"
    #endif
}
