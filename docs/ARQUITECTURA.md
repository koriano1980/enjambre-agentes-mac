# Arquitectura

App nativa de barra de menú (AppKit). El núcleo es un paquete Swift que también corre las pruebas en Linux. No hay servidor web de interfaz.

## Piezas

- `EnjambreNucleo` decide, habla con modelos y aplica la seguridad.
- `EnjambreApp` dibuja cursores, la barra, el chat, la voz y el control de otras apps. Solo se compila de verdad en macOS.

El cerebro por defecto no es Claude. Cada agente tiene `modalidad` (`local`, `online`, `gui`) y `proveedor` (`ollama`, `mlx`, `llamacpp`, `claude-cli`, `openai`, `gemini`, `grok`, `openrouter`, `gui`).

## Preset y cola

`MemoriaEquipo` lee la RAM. Con 20 GB o más se elige `pro-24`; si no, `mini-16`. Los agentes con `modelo: auto` reciben el nombre del preset. Coordinador y programador comparten el modelo grande.

`ColaModelos` deja una sola inferencia por clave de modelo y no admite otro modelo si la suma superaría `presupuesto_gb`. Ollama lleva `keep_alive` de 90 segundos para soltar memoria al terminar.

## Red

`SondaRed` dice si hay internet. En el Mac es `NWPathMonitor`. Sin red, `MesaDebate.ruta` marca dormidos a los agentes `online` y a las apps con `requiere_red`. La tarea se reasigna a un agente local con herramientas parecidas.

## Debate y chat

Si `debate.activo` es verdadero, cada participante escribe una propuesta, el coordinador local devuelve el JSON del plan y, si el plan es delicado o hubo sugerencias externas, la `Sala` espera aprobar o vetar.

La `Sala` es el chat de grupo. Origen `telegram` o `webhook` implica `sugerencia: true`. Esos textos no son una llamada a herramientas.

## Apps

`AdaptadorChat` sale de `config/adaptadores.yaml` y se fusiona con los de fábrica (Antigravity, ChatGPT, Claude, Muse, navegador). En el Mac, `OperadorMac` activa la app, busca el rol de accesibilidad, escribe el valor, pulsa enviar y lee el texto nuevo. Si no hay texto y hay permiso de pantalla, Vision hace OCR. Un captcha o un campo secreto cortan el intento.

`CandadoInterfaz` serializa ratón y teclado. Dos apps pueden usar accesibilidad a la vez; el puntero físico, no.

## Nodo entre Macs

TCP en el puerto 47831, una línea JSON por mensaje, token compartido. El trabajador solo responde `completar`. No hay HTML.

## Webhook

HTTP mínimo, JSON, HMAC-SHA256, apagado por defecto, atado a 127.0.0.1 salvo `exponer_lan`. No sirve una página.

## Seguridad

`Seguridad` clasifica el shell, las rutas y AppleScript antes de ejecutar. Catástrofes (`rm -rf /`, `diskutil erase`, `dd` sobre un disco) se rechazan. El resto de borrados y envíos piden confirmación. El atajo de parada es de Carbon, para que funcione aunque Accesibilidad esté denegada.
