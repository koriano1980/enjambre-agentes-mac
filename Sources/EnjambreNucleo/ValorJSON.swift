import Foundation

/// JSON de tamaño moderado, con enteros de 64 bits (los chat id de Telegram no caben en Double).
public enum ValorJSON: Equatable, Sendable {
    case nulo
    case bool(Bool)
    case entero(Int64)
    case numero(Double)
    case texto(String)
    case lista([ValorJSON])
    case objeto([String: ValorJSON])

    public var objeto: [String: ValorJSON]? {
        if case .objeto(let o) = self { return o }
        return nil
    }

    public var lista: [ValorJSON]? {
        if case .lista(let l) = self { return l }
        return nil
    }

    public var texto: String? {
        if case .texto(let t) = self { return t }
        return nil
    }

    public var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    public var entero: Int64? {
        switch self {
        case .entero(let e):
            return e
        case .numero(let d):
            guard d.rounded() == d, d >= Double(Int64.min), d <= Double(Int64.max) else { return nil }
            return Int64(d)
        default:
            return nil
        }
    }

    public var numero: Double? {
        switch self {
        case .numero(let d):
            return d
        case .entero(let e):
            return Double(e)
        default:
            return nil
        }
    }

    public subscript(clave: String) -> ValorJSON? {
        objeto?[clave]
    }

    public static func parsear(_ texto: String) throws -> ValorJSON {
        var parser = ParserJSON(texto)
        let valor = try parser.parsearValor()
        parser.saltarEspacios()
        if !parser.fin {
            throw ErrorFormato(mensaje: "JSON con texto sobrante en la posición \(parser.indice)")
        }
        return valor
    }

    public func datos() -> Data {
        Data(textoPlano.utf8)
    }

    public var textoPlano: String {
        switch self {
        case .nulo:
            return "null"
        case .bool(let b):
            return b ? "true" : "false"
        case .entero(let e):
            return String(e)
        case .numero(let d):
            if d.isNaN || d.isInfinite { return "null" }
            return String(d)
        case .texto(let t):
            return "\"" + escapar(t) + "\""
        case .lista(let lista):
            return "[" + lista.map(\.textoPlano).joined(separator: ",") + "]"
        case .objeto(let objeto):
            let pares = objeto.keys.sorted().map { clave in
                "\"" + escapar(clave) + "\":" + (objeto[clave]?.textoPlano ?? "null")
            }
            return "{" + pares.joined(separator: ",") + "}"
        }
    }
}

public struct ErrorFormato: Error, Equatable, CustomStringConvertible {
    public var mensaje: String
    public init(mensaje: String) { self.mensaje = mensaje }
    public var description: String { mensaje }
}

private func escapar(_ texto: String) -> String {
    var salida = ""
    for caracter in texto {
        switch caracter {
        case "\\": salida += "\\\\"
        case "\"": salida += "\\\""
        case "\n": salida += "\\n"
        case "\r": salida += "\\r"
        case "\t": salida += "\\t"
        default: salida.append(caracter)
        }
    }
    return salida
}

private struct ParserJSON {
    let caracteres: [Character]
    var indice = 0

    init(_ texto: String) {
        caracteres = Array(texto)
    }

    var fin: Bool { indice >= caracteres.count }

    mutating func saltarEspacios() {
        while indice < caracteres.count, caracteres[indice].isWhitespace {
            indice += 1
        }
    }

    mutating func parsearValor() throws -> ValorJSON {
        saltarEspacios()
        guard indice < caracteres.count else {
            throw ErrorFormato(mensaje: "JSON incompleto")
        }
        let c = caracteres[indice]
        switch c {
        case "{":
            return try parsearObjeto()
        case "[":
            return try parsearLista()
        case "\"":
            return .texto(try parsearCadena())
        case "t":
            try consumirLiteral("true")
            return .bool(true)
        case "f":
            try consumirLiteral("false")
            return .bool(false)
        case "n":
            try consumirLiteral("null")
            return .nulo
        case "-", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
            return try parsearNumero()
        default:
            throw ErrorFormato(mensaje: "Carácter JSON inesperado «\(c)»")
        }
    }

    mutating func parsearObjeto() throws -> ValorJSON {
        indice += 1
        var mapa: [String: ValorJSON] = [:]
        saltarEspacios()
        if mirar("}") {
            indice += 1
            return .objeto(mapa)
        }
        while true {
            saltarEspacios()
            guard mirar("\"") else {
                throw ErrorFormato(mensaje: "Se esperaba una clave JSON")
            }
            let clave = try parsearCadena()
            saltarEspacios()
            guard consumir(":") else {
                throw ErrorFormato(mensaje: "Se esperaba «:» tras la clave \(clave)")
            }
            mapa[clave] = try parsearValor()
            saltarEspacios()
            if consumir(",") { continue }
            if consumir("}") { break }
            throw ErrorFormato(mensaje: "Objeto JSON mal cerrado")
        }
        return .objeto(mapa)
    }

    mutating func parsearLista() throws -> ValorJSON {
        indice += 1
        var lista: [ValorJSON] = []
        saltarEspacios()
        if mirar("]") {
            indice += 1
            return .lista(lista)
        }
        while true {
            lista.append(try parsearValor())
            saltarEspacios()
            if consumir(",") { continue }
            if consumir("]") { break }
            throw ErrorFormato(mensaje: "Lista JSON mal cerrada")
        }
        return .lista(lista)
    }

    mutating func parsearCadena() throws -> String {
        guard consumir("\"") else {
            throw ErrorFormato(mensaje: "Se esperaba una cadena")
        }
        var salida = ""
        while indice < caracteres.count {
            let c = caracteres[indice]
            indice += 1
            if c == "\"" { return salida }
            if c == "\\" {
                guard indice < caracteres.count else {
                    throw ErrorFormato(mensaje: "Escape incompleto")
                }
                let e = caracteres[indice]
                indice += 1
                switch e {
                case "\"": salida.append("\"")
                case "\\": salida.append("\\")
                case "/": salida.append("/")
                case "n": salida.append("\n")
                case "r": salida.append("\r")
                case "t": salida.append("\t")
                case "u":
                    let hex = try leerHex(4)
                    if let escalar = UInt32(hex, radix: 16), let unicode = UnicodeScalar(escalar) {
                        salida.append(Character(unicode))
                    } else {
                        throw ErrorFormato(mensaje: "Escape unicode inválido")
                    }
                default:
                    salida.append(e)
                }
            } else {
                salida.append(c)
            }
        }
        throw ErrorFormato(mensaje: "Cadena JSON sin cerrar")
    }

    mutating func parsearNumero() throws -> ValorJSON {
        let inicio = indice
        if mirar("-") { indice += 1 }
        while indice < caracteres.count, caracteres[indice].isNumber {
            indice += 1
        }
        var flotante = false
        if mirar(".") {
            flotante = true
            indice += 1
            while indice < caracteres.count, caracteres[indice].isNumber {
                indice += 1
            }
        }
        if mirar("e") || mirar("E") {
            flotante = true
            indice += 1
            if mirar("+") || mirar("-") { indice += 1 }
            while indice < caracteres.count, caracteres[indice].isNumber {
                indice += 1
            }
        }
        let lexema = String(caracteres[inicio..<indice])
        if lexema == "-" || lexema.isEmpty {
            throw ErrorFormato(mensaje: "Número inválido")
        }
        if !flotante, let entero = Int64(lexema) {
            return .entero(entero)
        }
        guard let numero = Double(lexema) else {
            throw ErrorFormato(mensaje: "Número inválido: \(lexema)")
        }
        return .numero(numero)
    }

    mutating func consumirLiteral(_ literal: String) throws {
        for caracter in literal {
            guard indice < caracteres.count, caracteres[indice] == caracter else {
                throw ErrorFormato(mensaje: "Se esperaba \(literal)")
            }
            indice += 1
        }
    }

    mutating func leerHex(_ n: Int) throws -> String {
        guard indice + n <= caracteres.count else {
            throw ErrorFormato(mensaje: "Unicode incompleto")
        }
        let texto = String(caracteres[indice..<(indice + n)])
        indice += n
        return texto
    }

    func mirar(_ c: Character) -> Bool {
        indice < caracteres.count && caracteres[indice] == c
    }

    mutating func consumir(_ c: Character) -> Bool {
        guard mirar(c) else { return false }
        indice += 1
        return true
    }
}
