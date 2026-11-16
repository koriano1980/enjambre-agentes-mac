import Foundation

public struct PuntoNorm: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct CursorVisual: Equatable, Sendable, Identifiable {
    public var id: String
    public var nombre: String
    public var colorHex: String
    public var x: Double
    public var y: Double
    public var angulo: Double
    public var burbuja: String?
    public var opacidad: Double
    public var fantasma: Bool
    public var pulso: Double
    public var etiqueta: String
    public var dormido: Bool
    /// 1 es el tamaño de un cursor de trabajo. El enjambre del vídeo usa valores cerca de 0,5.
    public var escala: Double

    public init(id: String, nombre: String, colorHex: String, x: Double, y: Double, angulo: Double = -0.7, burbuja: String? = nil, opacidad: Double = 1, fantasma: Bool = false, pulso: Double = 0, etiqueta: String = "", dormido: Bool = false, escala: Double = 1) {
        self.id = id
        self.nombre = nombre
        self.colorHex = colorHex
        self.x = x
        self.y = y
        self.angulo = angulo
        self.burbuja = burbuja
        self.opacidad = opacidad
        self.fantasma = fantasma
        self.pulso = pulso
        self.etiqueta = etiqueta
        self.dormido = dormido
        self.escala = escala
    }
}

public struct LlamadaHerramienta: Equatable, Sendable {
    public var nombre: String
    public var argumentos: [String: ValorJSON]
    public var burbuja: String?
    public var cursor: PuntoNorm?
    public var pensamiento: String?

    public init(nombre: String, argumentos: [String: ValorJSON] = [:], burbuja: String? = nil, cursor: PuntoNorm? = nil, pensamiento: String? = nil) {
        self.nombre = nombre
        self.argumentos = argumentos
        self.burbuja = burbuja
        self.cursor = cursor
        self.pensamiento = pensamiento
    }

    public func texto(_ clave: String) -> String? {
        argumentos[clave]?.texto
    }

    public func numero(_ clave: String) -> Double? {
        argumentos[clave]?.numero
    }

    public func bool(_ clave: String) -> Bool? {
        argumentos[clave]?.bool
    }
}

public struct ResultadoHerramienta: Equatable, Sendable {
    public var salida: String
    public var esError: Bool
    public var cursor: PuntoNorm?
    public var burbuja: String?

    public init(salida: String, esError: Bool = false, cursor: PuntoNorm? = nil, burbuja: String? = nil) {
        self.salida = salida
        self.esError = esError
        self.cursor = cursor
        self.burbuja = burbuja
    }
}

public struct TareaPlan: Equatable, Sendable {
    public var id: String
    public var agente: String
    public var objetivo: String
    public var dependeDe: [String]

    public init(id: String, agente: String, objetivo: String, dependeDe: [String] = []) {
        self.id = id
        self.agente = agente
        self.objetivo = objetivo
        self.dependeDe = dependeDe
    }
}

public struct Plan: Equatable, Sendable {
    public var resumen: String
    public var tareas: [TareaPlan]

    public init(resumen: String, tareas: [TareaPlan]) {
        self.resumen = resumen
        self.tareas = tareas
    }
}

public enum ErrorPlan: Error, Equatable {
    case ciclo
}

public enum PlanificadorOlas {
    public static func olas(_ tareas: [TareaPlan]) throws -> [[TareaPlan]] {
        var pendientes: [String: TareaPlan] = [:]
        for tarea in tareas {
            pendientes[tarea.id] = tarea
        }
        var hechas = Set<String>()
        var resultado: [[TareaPlan]] = []
        while !pendientes.isEmpty {
            let listas = pendientes.values.filter { tarea in
                tarea.dependeDe.allSatisfy { dependencia in
                    pendientes[dependencia] == nil || hechas.contains(dependencia)
                }
            }
            if listas.isEmpty { throw ErrorPlan.ciclo }
            let ordenadas = listas.sorted { $0.id < $1.id }
            resultado.append(ordenadas)
            for tarea in ordenadas {
                pendientes[tarea.id] = nil
                hechas.insert(tarea.id)
            }
        }
        return resultado
    }
}

public enum ProtocoloAgente {
    public static func extraerJSON(_ texto: String) -> ValorJSON? {
        var limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        if let rangoInicio = limpio.range(of: "```") {
            var interior = limpio[rangoInicio.upperBound...]
            if interior.lowercased().hasPrefix("json") {
                interior = interior.dropFirst(4)
            }
            if let cierre = interior.range(of: "```") {
                limpio = String(interior[..<cierre.lowerBound])
            }
        }
        limpio = limpio.trimmingCharacters(in: .whitespacesAndNewlines)
        if let valor = try? ValorJSON.parsear(limpio) {
            return valor
        }
        guard let recorte = recortarJSON(limpio), let valor = try? ValorJSON.parsear(recorte) else {
            return nil
        }
        return valor
    }

    public static func decision(desde texto: String) -> LlamadaHerramienta? {
        guard let valor = extraerJSON(texto), let objeto = valor.objeto else { return nil }
        guard var nombre = objeto["herramienta"]?.texto ?? objeto["tool"]?.texto else { return nil }
        nombre = nombre.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if nombre.isEmpty { return nil }
        var argumentos = objeto["argumentos"]?.objeto ?? objeto["args"]?.objeto ?? [:]
        let reservadas: Set<String> = ["pensamiento", "herramienta", "argumentos", "args", "burbuja", "cursor", "estado", "resumen", "tool"]
        for (clave, valor) in objeto where !reservadas.contains(clave) && argumentos[clave] == nil {
            argumentos[clave] = valor
        }
        if nombre == "terminar" || nombre == "finalizar" || nombre == "hecho" {
            if argumentos["resumen"] == nil {
                if let resumen = objeto["resumen"]?.texto {
                    argumentos["resumen"] = .texto(resumen)
                } else if let burbuja = objeto["burbuja"]?.texto {
                    argumentos["resumen"] = .texto(burbuja)
                }
            }
        }
        return LlamadaHerramienta(
            nombre: nombre,
            argumentos: argumentos,
            burbuja: objeto["burbuja"]?.texto,
            cursor: punto(objeto["cursor"]),
            pensamiento: objeto["pensamiento"]?.texto
        )
    }

    public static func esFin(_ llamada: LlamadaHerramienta) -> Bool {
        ["terminar", "finalizar", "hecho"].contains(llamada.nombre)
    }

    public static func resumen(de llamada: LlamadaHerramienta) -> String {
        llamada.texto("resumen") ?? llamada.texto("resultado") ?? llamada.burbuja ?? "Listo."
    }

    public static func plan(desde texto: String) -> Plan? {
        guard let valor = extraerJSON(texto) else { return nil }
        let objeto: [String: ValorJSON]
        let lista: [ValorJSON]
        if let obj = valor.objeto {
            objeto = obj
            if let tareas = obj["tareas"]?.lista ?? obj["tasks"]?.lista {
                lista = tareas
            } else if obj["agente"] != nil || obj["objetivo"] != nil {
                lista = [.objeto(obj)]
            } else {
                return nil
            }
        } else if let arr = valor.lista {
            objeto = [:]
            lista = arr
        } else {
            return nil
        }
        var tareas: [TareaPlan] = []
        for (indice, item) in lista.enumerated() {
            guard let mapa = item.objeto else { continue }
            let objetivo = mapa["objetivo"]?.texto ?? mapa["tarea"]?.texto ?? mapa["descripcion"]?.texto ?? ""
            if objetivo.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let id = mapa["id"]?.texto?.trimmingCharacters(in: .whitespaces).nilSiVacio ?? "t\(indice + 1)"
            let agente = mapa["agente"]?.texto ?? mapa["agent"]?.texto ?? "programador"
            let depende = (mapa["depende_de"]?.lista ?? mapa["dependencias"]?.lista ?? []).compactMap { $0.texto ?? $0.entero.map(String.init) }
            tareas.append(TareaPlan(id: id, agente: agente, objetivo: objetivo, dependeDe: depende))
        }
        guard !tareas.isEmpty else { return nil }
        let resumen = objeto["resumen"]?.texto ?? ""
        return Plan(resumen: resumen, tareas: tareas)
    }
}

private func punto(_ valor: ValorJSON?) -> PuntoNorm? {
    guard let mapa = valor?.objeto, let x = mapa["x"]?.numero, let y = mapa["y"]?.numero else { return nil }
    return PuntoNorm(x: x, y: y)
}

private func recortarJSON(_ texto: String) -> String? {
    let caracteres = Array(texto)
    guard let inicio = caracteres.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
    let apertura = caracteres[inicio]
    let cierre: Character = apertura == "{" ? "}" : "]"
    var profundidad = 0
    var comillas = false
    var escapado = false
    for indice in inicio..<caracteres.count {
        let c = caracteres[indice]
        if escapado { escapado = false; continue }
        if c == "\\" && comillas { escapado = true; continue }
        if c == "\"" { comillas.toggle(); continue }
        if comillas { continue }
        if c == apertura { profundidad += 1 }
        if c == cierre {
            profundidad -= 1
            if profundidad == 0 {
                return String(caracteres[inicio...indice])
            }
        }
    }
    return nil
}

private extension String {
    var nilSiVacio: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

public func recortarTexto(_ texto: String, maximo: Int) -> String {
    if texto.count <= maximo { return texto }
    let indice = texto.index(texto.startIndex, offsetBy: maximo)
    return String(texto[..<indice]) + "\n… [recortado]"
}
