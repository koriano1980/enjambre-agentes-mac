import Foundation

public enum Prompts {
    public static func sistemaPlan(agentes: [AgenteConfig]) -> String {
        let lista = agentes.map { agente in
            "- \(agente.id) (\(agente.nombre), \(agente.modalidad.rawValue)): \(agente.rol) Herramientas: \(agente.herramientas.joined(separator: ", "))."
        }.joined(separator: "\n")
        return """
        Eres el orquestador de Enjambre de Agentes, en el Mac del usuario. Hablas español.
        Divide la orden en subtareas independientes cuando se pueda, y encadénalas con depende_de si una necesita el resultado de otra.
        Responde SOLO con un objeto JSON, sin markdown:
        {"resumen":"una frase","tareas":[{"id":"t1","agente":"programador","objetivo":"qué debe lograr","depende_de":[]}]}
        Agentes:
        \(lista)
        Usa como mucho \(max(agentes.count * 2, 4)) tareas. No inventes agentes. No ejecutes nada tú: solo planifica.
        """
    }

    public static func usuarioPlan(orden: String) -> String {
        "Orden del usuario:\n\(orden)"
    }

    public static func sistemaAgente(_ agente: AgenteConfig, pantalla: String) -> String {
        """
        Eres \(agente.nombre), un agente del enjambre en el Mac del usuario. \(agente.rol)
        Hablas español. No inventes resultados de herramientas: si no has llamado a una herramienta, no digas que lo hiciste.
        En cada turno responde SOLO con un objeto JSON, sin markdown:
        {"pensamiento":"breve","herramienta":"nombre","argumentos":{},"burbuja":"estado de pocas palabras","cursor":{"x":0.5,"y":0.4}}
        cursor usa coordenadas normalizadas de la pantalla (0,0 es la esquina superior izquierda). Pantalla: \(pantalla).
        Cuando el objetivo esté cumplido:
        {"herramienta":"terminar","argumentos":{"resumen":"qué quedó hecho, en español, para el usuario"}}
        Si una herramienta falla, cambia de estrategia o termina explicando el fallo. No pidas permiso para leer o editar dentro de la orden: el sistema ya confirma borrados, envíos y compras.
        Herramientas tuyas:
        \(CatalogoHerramientas.texto(para: agente.herramientas))
        """
    }

    public static func usuarioAgente(objetivo: String, historial: String, paso: Int, maxPasos: Int) -> String {
        """
        Objetivo: \(objetivo)
        Paso \(paso) de \(maxPasos).
        Historial de esta tarea:
        \(historial.isEmpty ? "(aún no hay)" : historial)
        """
    }

    public static func sistemaSintesis() -> String {
        "Resume para el usuario, en español claro y breve, qué hicieron los agentes. Texto plano, sin JSON y sin saludos largos. No inventes acciones que no estén en los resultados."
    }

    public static func usuarioSintesis(orden: String, resumenes: String) -> String {
        "Orden original:\n\(orden)\n\nResultados:\n\(resumenes)"
    }

    public static func reparacion(anterior: String) -> String {
        "Tu respuesta anterior no era JSON válido. Responde de nuevo únicamente con el objeto JSON pedido, sin markdown.\n\nRespuesta anterior:\n\(recortarTexto(anterior, maximo: 2000))"
    }
}

public enum CatalogoHerramientas {
    public static func texto(para nombres: [String]) -> String {
        let permitidas = Set(nombres)
        return descripciones.filter { permitidas.contains($0.0) }.map { "- \($0.0): \($0.1)" }.joined(separator: "\n")
    }

    private static let descripciones: [(String, String)] = [
        ("shell", #"{"comando":"echo hola"} ejecuta en zsh. Evita borrar; el sistema rechaza rm de la raíz y pide confirmación para borrar, push, sudo o enviar."#),
        ("leer_archivo", #"{"ruta":"~/notas.txt"} lee texto. Las credenciales piden confirmación."#),
        ("escribir_archivo", #"{"ruta":"~/notas.txt","contenido":"..."} crea o sustituye el archivo."#),
        ("editar_archivo", #"{"ruta":"~/notas.txt","buscar":"texto exacto","reemplazar":"nuevo","todas":false}"#),
        ("listar", #"{"ruta":"~/Documents"} lista la carpeta."#),
        ("esperar", #"{"segundos":1} espera como máximo 10 segundos."#),
        ("osascript", #"{"fuente":"tell application \\"Finder\\" to get name of startup disk"} AppleScript. Enviar correo o borrar pide confirmación."#),
        ("abrir", #"{"destino":"Safari"} o {"destino":"https://ejemplo.com"}."#),
        ("raton", #"{"accion":"mover|clic|doble|derecho|arrastrar|desplazar","x":100,"y":200,"normalizado":false,"x2":0,"y2":0,"dx":0,"dy":-200}. Origen: esquina superior izquierda, en puntos."#),
        ("teclado", #"{"texto":"hola"} o {"atajo":"cmd+s"}."#),
        ("captura", #"{} guarda una captura de pantalla y describe el archivo."#),
        ("ui_arbol", #"{} lista elementos de accesibilidad de la app al frente (rol, título, posición). Úsalo antes de hacer clic a ciegas."#),
        ("operar_chat", #"{"adaptador":"antigravity|chatgpt|claude|muse|navegador","texto":"pregunta"} abre esa app o web, escribe como una persona y lee la respuesta. No resuelvas captchas ni escribas contraseñas."#),
    ]
}
