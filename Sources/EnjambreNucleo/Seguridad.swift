import Foundation

public enum NivelRiesgo: Equatable, Sendable {
    case permitido
    case confirmar(String)
    case autorizarGUI(String)
    case rechazado(String)

    public var motivo: String? {
        switch self {
        case .permitido: return nil
        case .confirmar(let m), .autorizarGUI(let m), .rechazado(let m): return m
        }
    }

    var gravedad: Int {
        switch self {
        case .permitido: return 0
        case .autorizarGUI: return 1
        case .confirmar: return 2
        case .rechazado: return 3
        }
    }
}

public enum Seguridad {
    public static func combinar(_ niveles: [NivelRiesgo]) -> NivelRiesgo {
        niveles.max { $0.gravedad < $1.gravedad } ?? .permitido
    }

    public static func evaluarComandoShell(_ comando: String) -> NivelRiesgo {
        let original = comando.trimmingCharacters(in: .whitespacesAndNewlines)
        if original.isEmpty { return .confirmar("comando vacío") }
        var niveles: [NivelRiesgo] = [barridoCatastrofico(original)]
        if tuberíaAShell(original) {
            niveles.append(.confirmar("una tubería ejecuta un script remoto o un shell"))
        }
        for segmento in segmentosShell(original) {
            niveles.append(evaluarSegmento(segmento))
            for interno in extraerSustituciones(segmento) {
                niveles.append(evaluarComandoShell(interno))
            }
        }
        return combinar(niveles)
    }

    public static func evaluarRutaEscritura(_ ruta: String, permitidas: [String], home: String, directorio: String) -> NivelRiesgo {
        let canonica = RutasEnjambre.canonica(ruta, home: home, directorio: directorio)
        if esRutaDeSistemaProtegida(canonica) {
            return .rechazado("escritura en una ruta del sistema (\(canonica))")
        }
        if esRutaSensible(canonica) {
            return .confirmar("escritura sobre credenciales o llaves (\(canonica))")
        }
        let raices = permitidas.map { RutasEnjambre.canonica($0, home: home, directorio: directorio) }
        if raices.contains(where: { RutasEnjambre.estaDentro(canonica, de: $0) }) {
            return .permitido
        }
        if esRutaDeHerramientasLocales(canonica) {
            return .confirmar("escritura fuera de las rutas permitidas (\(canonica))")
        }
        return .confirmar("escritura fuera de las rutas permitidas (\(canonica))")
    }

    public static func evaluarRutaLectura(_ ruta: String, home: String, directorio: String) -> NivelRiesgo {
        let canonica = RutasEnjambre.canonica(ruta, home: home, directorio: directorio)
        if esRutaSensible(canonica) {
            return .confirmar("lectura de credenciales o llaves (\(canonica))")
        }
        return .permitido
    }

    public static func evaluarAppleScript(_ fuente: String) -> NivelRiesgo {
        let bajo = fuente.lowercased()
        if bajo.contains("delete") || bajo.contains("empty") && bajo.contains("trash") || bajo.contains("shut down") || bajo.contains("restart") {
            return .confirmar("AppleScript destructivo o que apaga el Mac")
        }
        let envia = bajo.contains(" send") || bajo.hasPrefix("send") || bajo.contains("send ")
        let appMensaje = bajo.contains("mail") || bajo.contains("messages") || bajo.contains("telegram") || bajo.contains("whatsapp") || bajo.contains("correo")
        if envia && appMensaje {
            return .confirmar("envío de un mensaje o correo")
        }
        if bajo.contains("keystroke") || bajo.contains("click") || bajo.contains("perform") || (bajo.contains("system events") && (bajo.contains("key") || bajo.contains("click"))) {
            return .autorizarGUI("AppleScript que pulsa teclas o hace clic")
        }
        return .permitido
    }

    public static func evaluarTeclado(_ texto: String) -> NivelRiesgo {
        let bajo = texto.lowercased()
        let disparadores = ["enviar", "send", "comprar", "purchase", "borrar", "eliminar", "delete"]
        for palabra in disparadores where contienePalabra(bajo, palabra) {
            return .confirmar("el texto parece \(palabra) algo")
        }
        return .autorizarGUI("escribir con el teclado")
    }

    public static func evaluarRaton(accion: String) -> NivelRiesgo {
        switch accion.lowercased() {
        case "mover", "move":
            return .permitido
        default:
            return .autorizarGUI("controlar el ratón (\(accion))")
        }
    }

    public static func evaluarAbrir(_ destino: String) -> NivelRiesgo {
        let bajo = destino.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if bajo.hasPrefix("mailto:") { return .confirmar("abrir un enlace para enviar correo") }
        if contienePalabra(bajo, "comprar") || contienePalabra(bajo, "purchase") || bajo.contains("apple.com/shop") || bajo.contains("/buy") {
            return .confirmar("abrir una página de compra")
        }
        return .permitido
    }
}

private func barridoCatastrofico(_ comando: String) -> NivelRiesgo {
    let bajo = comando.lowercased()
    let compacto = bajo.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "'", with: "")
    if compacto.contains(":(){") || compacto.contains(":(){:|:&};:") {
        return .rechazado("bomba de procesos")
    }
    if compacto.contains("mkfs") || compacto.contains("newfs") {
        return .rechazado("formatear un disco")
    }
    if bajo.contains("diskutil") && (bajo.contains("erase") || bajo.contains("partitiondisk") || bajo.contains("deletedisk") || bajo.contains("resetfusion")) {
        return .rechazado("borrar un disco con diskutil")
    }
    if bajo.contains("dd") && bajo.contains("of=/dev/") {
        return .rechazado("escribir con dd sobre un dispositivo")
    }
    if bajo.range(of: #">\s*/dev/(sd|disk|rdisk)"#, options: .regularExpression) != nil {
        return .rechazado("redirigir salida a un disco")
    }
    if compacto.contains("rmtree(/)") || compacto.contains("rmtree(\"/\")") || compacto.contains("removedirs(\"/\")") {
        return .rechazado("borrado recursivo de la raíz desde un script")
    }
    return .permitido
}

private func evaluarSegmento(_ segmento: String) -> NivelRiesgo {
    let limpio = segmento.trimmingCharacters(in: .whitespacesAndNewlines)
    if limpio.isEmpty { return .permitido }
    let (binario, resto, sudo) = comandoBase(limpio)
    var niveles: [NivelRiesgo] = []
    if sudo { niveles.append(.confirmar("usa sudo")) }
    switch binario {
    case "rm", "unlink", "trash", "srm", "rmdir":
        niveles.append(evaluarBorrado(binario: binario, resto: resto))
    case "git":
        niveles.append(evaluarGit(resto))
    case "sudo":
        niveles.append(.confirmar("usa sudo"))
    case "kill", "pkill", "killall":
        niveles.append(.confirmar("terminar procesos"))
    case "shutdown", "reboot", "halt", "poweroff":
        niveles.append(.confirmar("apagar o reiniciar el Mac"))
    case "chmod", "chown", "chflags":
        niveles.append(.confirmar("cambiar permisos o dueño"))
    case "launchctl":
        if resto.contains("bootout") || resto.contains("unload") || resto.contains("remove") {
            niveles.append(.confirmar("cambiar agentes de launchd"))
        }
    case "defaults":
        if primerToken(resto) == "delete" { niveles.append(.confirmar("borrar preferencias")) }
    case "curl", "wget":
        niveles.append(evaluarDescarga(resto))
    case "npm", "pnpm", "yarn":
        if contienePalabra(resto, "publish") { niveles.append(.confirmar("publicar un paquete")) }
    case "gh":
        if resto.contains("pr merge") || resto.contains("release") || resto.contains("repo delete") {
            niveles.append(.confirmar("publicar o fusionar en GitHub"))
        }
    case "mail", "sendmail", "postfix":
        niveles.append(.confirmar("enviar correo"))
    case "find":
        if resto.contains("-delete") || resto.contains("-exec rm") {
            niveles.append(.confirmar("find que borra archivos"))
        }
    case "mkfs", "mkfs.apfs", "diskutil", "dd":
        niveles.append(.rechazado("operación de disco"))
    default:
        break
    }
    if resto.contains("npm publish") || contienePalabra(resto, "purchase") {
        niveles.append(.confirmar("publicar o comprar"))
    }
    return Seguridad.combinar(niveles)
}

private func evaluarBorrado(binario: String, resto: String) -> NivelRiesgo {
    let tokens = tokenizar(resto)
    var recursivo = binario == "rm" && (resto.contains("--recursive") || flagsContienen(tokens, letra: "r"))
    if binario != "rm" { recursivo = true }
    var objetivos: [String] = []
    var finDeFlags = false
    for token in tokens {
        if !finDeFlags, token == "--" { finDeFlags = true; continue }
        if !finDeFlags, token.hasPrefix("-") { continue }
        objetivos.append(token)
    }
    for objetivo in objetivos {
        if esObjetivoCatastrofico(objetivo) && (recursivo || binario == "rm") {
            return .rechazado("borrado de \(objetivo): es la raíz, el sistema o toda la carpeta personal")
        }
    }
    if binario == "rm" && objetivos.isEmpty && flagsContienen(tokens, letra: "r") {
        return .confirmar("rm recursivo")
    }
    return .confirmar("borrado con \(binario)")
}

private func evaluarGit(_ resto: String) -> NivelRiesgo {
    let sub = primerToken(resto)
    switch sub {
    case "push":
        return .confirmar("git push publica commits")
    case "clean":
        return .confirmar("git clean borra archivos sin seguimiento")
    case "reset":
        if resto.contains("--hard") { return .confirmar("git reset --hard descarta cambios") }
        return .permitido
    case "rebase":
        return .confirmar("git rebase reescribe historia")
    case "checkout", "restore", "switch":
        if resto.contains(" -- ") || resto.hasSuffix(" --") || resto.contains("-- .") || resto.contains("--hard") {
            return .confirmar("git puede descartar cambios locales")
        }
        return .permitido
    default:
        return .permitido
    }
}

private func evaluarDescarga(_ resto: String) -> NivelRiesgo {
    let bajo = resto.lowercased()
    if bajo.contains("-d ") || bajo.contains("--data") || bajo.contains("--json") || bajo.contains("-f ") || bajo.contains("--form") {
        return .confirmar("petición que envía datos")
    }
    if bajo.contains("-x") && (bajo.contains("post") || bajo.contains("put") || bajo.contains("delete")) {
        return .confirmar("petición que modifica un servidor")
    }
    if bajo.contains("--upload-file") || bajo.contains("-t ") {
        return .confirmar("subida de un archivo")
    }
    return .permitido
}

func segmentosShell(_ comando: String) -> [String] {
    var segmentos: [String] = []
    var actual = ""
    var comillas: Character?
    var escapado = false
    let caracteres = Array(comando)
    var i = 0
    func cerrar() {
        let trozo = actual.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trozo.isEmpty { segmentos.append(trozo) }
        actual = ""
    }
    while i < caracteres.count {
        let c = caracteres[i]
        if escapado {
            actual.append(c)
            escapado = false
            i += 1
            continue
        }
        if c == "\\", comillas != "'" {
            actual.append(c)
            escapado = true
            i += 1
            continue
        }
        if c == "\"" || c == "'" {
            if comillas == c { comillas = nil } else if comillas == nil { comillas = c }
            actual.append(c)
            i += 1
            continue
        }
        if comillas == nil {
            if c == "\n" || c == ";" {
                cerrar(); i += 1; continue
            }
            if c == "&", i + 1 < caracteres.count, caracteres[i + 1] == "&" {
                cerrar(); i += 2; continue
            }
            if c == "|", i + 1 < caracteres.count, caracteres[i + 1] == "|" {
                cerrar(); i += 2; continue
            }
            if c == "|" {
                cerrar(); i += 1; continue
            }
        }
        actual.append(c)
        i += 1
    }
    cerrar()
    return segmentos.isEmpty ? [comando] : segmentos
}

private func tuberíaAShell(_ comando: String) -> Bool {
    let bajo = comando.lowercased()
    return bajo.contains("| sh") || bajo.contains("| bash") || bajo.contains("| zsh") || bajo.contains("|sh") || bajo.contains("|bash")
}

private func extraerSustituciones(_ segmento: String) -> [String] {
    var internos: [String] = []
    let caracteres = Array(segmento)
    var i = 0
    while i < caracteres.count {
        if caracteres[i] == "`" {
            i += 1
            var interno = ""
            while i < caracteres.count, caracteres[i] != "`" {
                interno.append(caracteres[i]); i += 1
            }
            if !interno.isEmpty { internos.append(interno) }
        } else if caracteres[i] == "$", i + 1 < caracteres.count, caracteres[i + 1] == "(" {
            i += 2
            var profundidad = 1
            var interno = ""
            while i < caracteres.count, profundidad > 0 {
                if caracteres[i] == "(" { profundidad += 1 }
                if caracteres[i] == ")" { profundidad -= 1; if profundidad == 0 { break } }
                interno.append(caracteres[i])
                i += 1
            }
            if !interno.isEmpty { internos.append(interno) }
        }
        i += 1
    }
    return internos
}

private func comandoBase(_ segmento: String) -> (String, String, Bool) {
    var tokens = tokenizar(segmento)
    var sudo = false
    while let primero = tokens.first {
        if primero.contains("="), !primero.hasPrefix("="), !primero.hasPrefix("/") {
            tokens.removeFirst()
            continue
        }
        break
    }
    if tokens.first == "sudo" {
        sudo = true
        tokens.removeFirst()
        while let flag = tokens.first, flag.hasPrefix("-") {
            tokens.removeFirst()
        }
    }
    if tokens.first == "command" || tokens.first == "nocorrect" || tokens.first == "builtin" {
        tokens.removeFirst()
    }
    let binario = (tokens.first ?? "").split(separator: "/").last.map(String.init)?.lowercased() ?? ""
    let resto = tokens.dropFirst().joined(separator: " ")
    return (binario, resto, sudo)
}

func tokenizar(_ texto: String) -> [String] {
    var tokens: [String] = []
    var actual = ""
    var comillas: Character?
    for caracter in texto {
        if let comillasActuales = comillas {
            if caracter == comillasActuales { comillas = nil } else { actual.append(caracter) }
            continue
        }
        if caracter == "\"" || caracter == "'" {
            comillas = caracter
            continue
        }
        if caracter.isWhitespace {
            if !actual.isEmpty { tokens.append(actual); actual = "" }
            continue
        }
        actual.append(caracter)
    }
    if !actual.isEmpty { tokens.append(actual) }
    return tokens
}

private func primerToken(_ texto: String) -> String {
    tokenizar(texto).first?.lowercased() ?? ""
}

private func flagsContienen(_ tokens: [String], letra: Character) -> Bool {
    for token in tokens where token.hasPrefix("-") && !token.hasPrefix("--") {
        if token.contains(letra) { return true }
    }
    return false
}

func esObjetivoCatastrofico(_ token: String) -> Bool {
    var t = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
    t = t.replacingOccurrences(of: "\\ ", with: " ")
    let bajos = ["/", "/*", "/.", "/*/", "~", "~/", "~/*", "$home", "$home/", "$home/*", "${home}", "${home}/", "${home}/*"]
    if bajos.contains(t.lowercased()) { return true }
    var limpio = t
    if limpio.hasSuffix("/*") { limpio = String(limpio.dropLast(2)) }
    if limpio.count > 1 && limpio.hasSuffix("/") { limpio = String(limpio.dropLast()) }
    let sistemas: Set<String> = ["/usr", "/bin", "/sbin", "/etc", "/var", "/private", "/system", "/users", "/applications", "/library", "/boot", "/dev", "/opt", "/volumes"]
    return sistemas.contains(limpio.lowercased())
}

func esRutaDeSistemaProtegida(_ ruta: String) -> Bool {
    let sistemas = ["/usr", "/bin", "/sbin", "/etc", "/var", "/private", "/system", "/library", "/applications", "/boot", "/dev"]
    let excepciones = ["/usr/local", "/opt/homebrew", "/var/folders"]
    if excepciones.contains(where: { RutasEnjambre.estaDentro(ruta, de: $0) }) {
        return false
    }
    return sistemas.contains { RutasEnjambre.estaDentro(ruta, de: $0) || ruta == $0 }
}

func esRutaDeHerramientasLocales(_ ruta: String) -> Bool {
    ["/usr/local", "/opt/homebrew"].contains { RutasEnjambre.estaDentro(ruta, de: $0) }
}

func esRutaSensible(_ ruta: String) -> Bool {
    let bajo = ruta.lowercased()
    let marcas = ["/.ssh/", "/.aws/", "/.gnupg/", "/.netrc", "/keychains/", "credentials", "/.config/gh/", "cookies", "id_rsa", "id_ed25519", ".pem"]
    if bajo.hasSuffix("/.ssh") || bajo.hasSuffix("/.aws") || bajo.hasSuffix("/.gnupg") { return true }
    return marcas.contains { bajo.contains($0) }
}

func contienePalabra(_ texto: String, _ palabra: String) -> Bool {
    var resto = Substring(texto)
    while let rango = resto.range(of: palabra) {
        let antesOK: Bool
        if rango.lowerBound == resto.startIndex {
            antesOK = true
        } else {
            let anterior = resto[resto.index(before: rango.lowerBound)]
            antesOK = !anterior.isLetter && !anterior.isNumber
        }
        let despuesOK: Bool
        if rango.upperBound == resto.endIndex {
            despuesOK = true
        } else {
            let siguiente = resto[rango.upperBound]
            despuesOK = !siguiente.isLetter && !siguiente.isNumber
        }
        if antesOK && despuesOK { return true }
        resto = resto[rango.upperBound...]
    }
    return false
}
