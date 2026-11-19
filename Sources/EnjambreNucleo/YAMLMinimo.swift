import Foundation

/// Subconjunto de YAML suficiente para la configuración: mapas, listas, escalares,
/// comentarios, comillas y flujos en una línea (`[a, b]`, `{ x: 1 }`).
public enum YAMLMinimo {
    public static func parsear(_ texto: String) throws -> ValorJSON {
        let lineas = preparar(texto)
        var parser = ParserYAML(lineas: lineas)
        if parser.fin { return .objeto([:]) }
        let valor = try parser.parsearNodo(indentacionMinima: 0)
        return valor ?? .objeto([:])
    }
}

private struct LineaYAML {
    var numero: Int
    var indentacion: Int
    var contenido: String
}

private func preparar(_ texto: String) -> [LineaYAML] {
    var salida: [LineaYAML] = []
    let crudas = texto.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    for (indice, cruda) in crudas.enumerated() {
        let sinComentario = quitarComentario(String(cruda))
        let expandida = sinComentario.replacingOccurrences(of: "\t", with: "  ")
        let indentacion = expandida.prefix(while: { $0 == " " }).count
        let contenido = String(expandida.drop(while: { $0 == " " })).trimmingCharacters(in: .whitespaces)
        if contenido.isEmpty { continue }
        salida.append(LineaYAML(numero: indice + 1, indentacion: indentacion, contenido: contenido))
    }
    return salida
}

private func quitarComentario(_ linea: String) -> String {
    var entreComillas: Character?
    var escapado = false
    var resultado: [Character] = []
    for caracter in linea {
        if escapado {
            resultado.append(caracter)
            escapado = false
            continue
        }
        if caracter == "\\", entreComillas == "\"" {
            resultado.append(caracter)
            escapado = true
            continue
        }
        if caracter == "\"" || caracter == "'" {
            if entreComillas == caracter {
                entreComillas = nil
            } else if entreComillas == nil {
                entreComillas = caracter
            }
            resultado.append(caracter)
            continue
        }
        if caracter == "#", entreComillas == nil {
            break
        }
        resultado.append(caracter)
    }
    while let ultimo = resultado.last, ultimo == " " || ultimo == "\t" {
        resultado.removeLast()
    }
    return String(resultado)
}

private struct ParserYAML {
    let lineas: [LineaYAML]
    var indice = 0

    var fin: Bool { indice >= lineas.count }

    mutating func parsearNodo(indentacionMinima: Int) throws -> ValorJSON? {
        guard indice < lineas.count else { return nil }
        let linea = lineas[indice]
        if linea.indentacion < indentacionMinima { return nil }
        if linea.contenido.hasPrefix("- ") || linea.contenido == "-" {
            return try parsearLista(indentacion: linea.indentacion)
        }
        if esClave(linea.contenido) {
            return try parsearMapa(indentacion: linea.indentacion)
        }
        throw ErrorFormato(mensaje: "Línea \(linea.numero): no entiendo «\(linea.contenido)»")
    }

    mutating func parsearMapa(indentacion: Int) throws -> ValorJSON {
        var mapa: [String: ValorJSON] = [:]
        while indice < lineas.count {
            let linea = lineas[indice]
            if linea.indentacion < indentacion { break }
            if linea.indentacion > indentacion {
                throw ErrorFormato(mensaje: "Línea \(linea.numero): sangría inesperada")
            }
            if linea.contenido.hasPrefix("- ") {
                break
            }
            let (clave, resto) = dividirClave(linea.contenido)
            guard let clave else {
                throw ErrorFormato(mensaje: "Línea \(linea.numero): se esperaba una clave")
            }
            indice += 1
            mapa[clave] = try valorDeClave(resto: resto, indentacion: indentacion, numero: linea.numero)
        }
        return .objeto(mapa)
    }

    mutating func parsearLista(indentacion: Int) throws -> ValorJSON {
        var lista: [ValorJSON] = []
        while indice < lineas.count {
            let linea = lineas[indice]
            if linea.indentacion < indentacion { break }
            if linea.indentacion > indentacion {
                throw ErrorFormato(mensaje: "Línea \(linea.numero): sangría inesperada en la lista")
            }
            guard linea.contenido.hasPrefix("- ") || linea.contenido == "-" else { break }
            let resto: String
            if linea.contenido == "-" {
                resto = ""
            } else {
                resto = String(linea.contenido.dropFirst(2))
            }
            indice += 1
            if resto.isEmpty {
                if let anidado = try parsearNodo(indentacionMinima: indentacion + 1) {
                    lista.append(anidado)
                } else {
                    lista.append(.nulo)
                }
                continue
            }
            if esClave(resto), !resto.hasPrefix("{"), !resto.hasPrefix("[") {
                var mapa: [String: ValorJSON] = [:]
                let (clave, valorInicial) = dividirClave(resto)
                if let clave {
                    mapa[clave] = try valorDeClave(resto: valorInicial, indentacion: indentacion, numero: linea.numero, consumirSiguientes: false)
                }
                let columnaClave = indentacion + 2
                while indice < lineas.count {
                    let siguiente = lineas[indice]
                    if siguiente.indentacion < columnaClave { break }
                    if siguiente.contenido.hasPrefix("- "), siguiente.indentacion == indentacion { break }
                    if siguiente.indentacion > columnaClave, mapa.isEmpty {
                        break
                    }
                    if siguiente.indentacion == columnaClave || (siguiente.indentacion > indentacion && esClave(siguiente.contenido) && !siguiente.contenido.hasPrefix("- ")) {
                        let (claveAnidada, restoAnidado) = dividirClave(siguiente.contenido)
                        guard let claveAnidada else { break }
                        indice += 1
                        mapa[claveAnidada] = try valorDeClave(
                            resto: restoAnidado,
                            indentacion: siguiente.indentacion,
                            numero: siguiente.numero
                        )
                    } else {
                        break
                    }
                }
                lista.append(.objeto(mapa))
            } else {
                lista.append(try parsearEscalar(resto, numero: linea.numero))
            }
        }
        return .lista(lista)
    }

    mutating func valorDeClave(resto: String, indentacion: Int, numero: Int, consumirSiguientes: Bool = true) throws -> ValorJSON {
        let limpio = resto.trimmingCharacters(in: .whitespaces)
        if limpio == "|" || limpio == ">" {
            return try bloque(plegado: limpio == ">", indentacionPadre: indentacion)
        }
        if limpio.isEmpty {
            if indice < lineas.count, lineas[indice].indentacion > indentacion {
                return try parsearNodo(indentacionMinima: indentacion + 1) ?? .nulo
            }
            return .nulo
        }
        return try parsearEscalar(limpio, numero: numero)
    }

    mutating func bloque(plegado: Bool, indentacionPadre: Int) throws -> ValorJSON {
        var trozos: [String] = []
        var indentacionBloque: Int?
        while indice < lineas.count {
            let linea = lineas[indice]
            if linea.indentacion <= indentacionPadre { break }
            if indentacionBloque == nil { indentacionBloque = linea.indentacion }
            let base = indentacionBloque ?? linea.indentacion
            let extra = max(0, linea.indentacion - base)
            let texto = String(repeating: " ", count: extra) + linea.contenido
            trozos.append(texto)
            indice += 1
        }
        if plegado {
            return .texto(trozos.joined(separator: " "))
        }
        return .texto(trozos.joined(separator: "\n"))
    }
}

private func esClave(_ texto: String) -> Bool {
    if texto.hasPrefix("- ") { return false }
    if texto.hasPrefix("{") || texto.hasPrefix("[") || texto.hasPrefix("\"") || texto.hasPrefix("'") {
        return false
    }
    return dividirClave(texto).0 != nil
}

private func dividirClave(_ texto: String) -> (String?, String) {
    var entreComillas: Character?
    var escapado = false
    let caracteres = Array(texto)
    var indice = 0
    while indice < caracteres.count {
        let c = caracteres[indice]
        if escapado {
            escapado = false
            indice += 1
            continue
        }
        if c == "\\", entreComillas == "\"" {
            escapado = true
            indice += 1
            continue
        }
        if c == "\"" || c == "'" {
            if entreComillas == c { entreComillas = nil }
            else if entreComillas == nil { entreComillas = c }
            indice += 1
            continue
        }
        if c == ":", entreComillas == nil {
            let siguienteEsSeparador = indice + 1 == caracteres.count || caracteres[indice + 1].isWhitespace || caracteres[indice + 1] == "#"
            let anteriorNoEsSigno = indice > 0
            if siguienteEsSeparador && anteriorNoEsSigno {
                let clave = String(caracteres[..<indice]).trimmingCharacters(in: .whitespaces)
                let resto = String(caracteres[(indice + 1)...]).trimmingCharacters(in: .whitespaces)
                if clave.isEmpty { return (nil, texto) }
                return (clave, resto)
            }
        }
        indice += 1
    }
    return (nil, texto)
}

private func parsearEscalar(_ texto: String, numero: Int) throws -> ValorJSON {
    let limpio = texto.trimmingCharacters(in: .whitespaces)
    if limpio.hasPrefix("[") || limpio.hasPrefix("{") {
        return try parsearFlujo(limpio, numero: numero)
    }
    if (limpio.hasPrefix("\"") && limpio.hasSuffix("\"")) || (limpio.hasPrefix("'") && limpio.hasSuffix("'") && limpio.count >= 2) {
        if limpio.hasPrefix("'") {
            let interior = String(limpio.dropFirst().dropLast())
            return .texto(interior.replacingOccurrences(of: "''", with: "'"))
        }
        return .texto(try decodificarComillasDobles(String(limpio.dropFirst().dropLast())))
    }
    switch limpio.lowercased() {
    case "null", "~", "nil":
        return .nulo
    case "true", "yes", "sí", "si", "on":
        return .bool(true)
    case "false", "no", "off":
        return .bool(false)
    default:
        break
    }
    if let numero = numeroYAML(limpio) {
        return numero
    }
    return .texto(limpio)
}

private func numeroYAML(_ texto: String) -> ValorJSON? {
    if texto.contains(".") || texto.contains("e") || texto.contains("E") {
        if let d = Double(texto) { return .numero(d) }
        return nil
    }
    if let e = Int64(texto) { return .entero(e) }
    return nil
}

private func decodificarComillasDobles(_ texto: String) throws -> String {
    var salida = ""
    var escapado = false
    for caracter in texto {
        if escapado {
            switch caracter {
            case "n": salida.append("\n")
            case "t": salida.append("\t")
            case "r": salida.append("\r")
            case "\"": salida.append("\"")
            case "\\": salida.append("\\")
            default: salida.append(caracter)
            }
            escapado = false
        } else if caracter == "\\" {
            escapado = true
        } else {
            salida.append(caracter)
        }
    }
    return salida
}

private func parsearFlujo(_ texto: String, numero: Int) throws -> ValorJSON {
    var parser = ParserFlujo(caracteres: Array(texto), numeroLinea: numero)
    let valor = try parser.parsearValor()
    parser.saltar()
    if !parser.fin {
        throw ErrorFormato(mensaje: "Línea \(numero): flujo YAML con texto sobrante")
    }
    return valor
}

private struct ParserFlujo {
    let caracteres: [Character]
    var indice = 0
    let numeroLinea: Int

    var fin: Bool { indice >= caracteres.count }

    mutating func saltar() {
        while indice < caracteres.count, caracteres[indice].isWhitespace { indice += 1 }
    }

    mutating func parsearValor() throws -> ValorJSON {
        saltar()
        if mirar("[") { return try parsearLista() }
        if mirar("{") { return try parsearMapa() }
        return try parsearEscalarHastaSeparador()
    }

    mutating func parsearLista() throws -> ValorJSON {
        indice += 1
        var lista: [ValorJSON] = []
        saltar()
        if consumir("]") { return .lista([]) }
        while true {
            lista.append(try parsearValor())
            saltar()
            if consumir(",") { continue }
            if consumir("]") { break }
            throw ErrorFormato(mensaje: "Línea \(numeroLinea): lista en línea mal cerrada")
        }
        return .lista(lista)
    }

    mutating func parsearMapa() throws -> ValorJSON {
        indice += 1
        var mapa: [String: ValorJSON] = [:]
        saltar()
        if consumir("}") { return .objeto([:]) }
        while true {
            saltar()
            let claveValor = try leerClaveFlujo()
            saltar()
            guard consumir(":") else {
                throw ErrorFormato(mensaje: "Línea \(numeroLinea): se esperaba «:» en el mapa")
            }
            mapa[claveValor] = try parsearValor()
            saltar()
            if consumir(",") { continue }
            if consumir("}") { break }
            throw ErrorFormato(mensaje: "Línea \(numeroLinea): mapa en línea mal cerrado")
        }
        return .objeto(mapa)
    }

    mutating func leerClaveFlujo() throws -> String {
        saltar()
        if mirar("\"") || mirar("'") {
            let valor = try parsearEscalarHastaSeparador()
            return valor.texto ?? ""
        }
        let inicio = indice
        while indice < caracteres.count {
            let c = caracteres[indice]
            if c == ":" || c == "}" || c == "," { break }
            indice += 1
        }
        let clave = String(caracteres[inicio..<indice]).trimmingCharacters(in: .whitespaces)
        if clave.isEmpty {
            throw ErrorFormato(mensaje: "Línea \(numeroLinea): clave vacía")
        }
        return clave
    }

    mutating func parsearEscalarHastaSeparador() throws -> ValorJSON {
        saltar()
        if mirar("\"") {
            indice += 1
            var salida = ""
            var escapado = false
            while indice < caracteres.count {
                let c = caracteres[indice]
                indice += 1
                if escapado {
                    salida.append(c)
                    escapado = false
                    continue
                }
                if c == "\\" { escapado = true; continue }
                if c == "\"" { return .texto(salida) }
                salida.append(c)
            }
            throw ErrorFormato(mensaje: "Línea \(numeroLinea): comillas sin cerrar")
        }
        if mirar("'") {
            indice += 1
            var salida = ""
            while indice < caracteres.count {
                let c = caracteres[indice]
                indice += 1
                if c == "'" { return .texto(salida) }
                salida.append(c)
            }
            throw ErrorFormato(mensaje: "Línea \(numeroLinea): comillas simples sin cerrar")
        }
        let inicio = indice
        var profundidad = 0
        while indice < caracteres.count {
            let c = caracteres[indice]
            if c == "[" || c == "{" { profundidad += 1 }
            if c == "]" || c == "}" {
                if profundidad == 0 { break }
                profundidad -= 1
            }
            if profundidad == 0, c == "," { break }
            indice += 1
        }
        let lexema = String(caracteres[inicio..<indice]).trimmingCharacters(in: .whitespaces)
        return try parsearEscalar(lexema, numero: numeroLinea)
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
