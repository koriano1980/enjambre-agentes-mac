# Enjambre de Agentes

Varios agentes trabajan en tu Mac a la vez, y tú los ves: cada uno tiene un cursor de color, su nombre y una burbuja con lo que está haciendo. No es una página web. Es una app de barra de menú para macOS, pensada para un MacBook Pro Apple Silicon de 24 GB y un Mac mini M4 de 16 GB.

Por defecto el cerebro es **local y funciona sin internet** (Ollama). Si hay red, entran agentes en la nube y, si tú quieres, apps de chat que el enjambre maneja como lo haría una persona. Nada de eso se ejecuta solo: tú das la orden, y las acciones destructivas piden confirmación.

## Qué hace

- Parte una orden en subtareas y las reparte.
- Antes de actuar, los agentes pueden **debatir** (propuesta, crítica, fusión). El coordinador es un modelo local.
- Dibuja un cursor por agente, encima de todo, que no roba los clics. El ratón y el teclado reales van en cola: hay uno solo.
- Abre Antigravity, ChatGPT, Claude, Muse (Meta AI en meta.ai) o el navegador, escribe en el cuadro y lee la respuesta. Primero por Accesibilidad; si no hay texto, por una captura y el reconocimiento de texto de Apple (Vision).
- Chat de grupo nativo: escribes o hablas, mencionas con `@Programador`, apruebas o vetas el plan.
- Telegram (tu bot, tu chat) y, si lo enciendes, un endpoint JSON firmado para que otros agentes (por ejemplo un bot de Grok) dejen **sugerencias**. Esas sugerencias no se ejecutan solas.
- Voz en español en el dispositivo, cuando macOS lo permite.
- Parada inmediata: `⌃⌥⌘K` o el botón rojo.

El modo demostración anima los cursores y un debate de ejemplo **sin modelos y sin Claude**.

## Qué no hace

- No abre un panel en el navegador ni en `localhost`.
- No gasta la API de pago de Anthropic por defecto. Claude Code, si lo tienes instalado y con la sesión iniciada, solo lo usa el agente Investigador cuando hay internet, contra tu suscripción.
- No resuelve captchas ni escribe contraseñas. Si una app pide login, entras tú.
- No borra el disco. `rm -rf /`, `diskutil erase` y cosas parecidas se rechazan. Otros borrados, envíos y compras piden confirmación.

HyperFrames (el proyecto de HeyGen, licencia Apache-2.0) es un render de vídeo en HTML. No tiene un overlay nativo que se pueda reutilizar sin meter una web, así que los cursores están dibujados con AppKit. La idea visual viene de las capturas del estudio, no de ese código.

## Requisitos

- macOS 14 o posterior, Apple Silicon.
- Swift, el que traen las herramientas de Xcode (`xcode-select --install`).
- [Ollama](https://ollama.com) para los modelos locales.
- Opcional: Claude Code (`claude` y `claude` /login) para el investigador en línea.
- Opcional: claves propias si quieres OpenAI, Gemini, Grok u OpenRouter. Sin clave, ese agente no entra.
- Opcional: las apps ChatGPT, Claude y Antigravity, con la sesión ya iniciada por ti.

## Presets según la RAM

La app lee la memoria y elige un preset. Puedes forzarlo en `hardware.preset` (`auto`, `pro-24` o `mini-16`).

Los tamaños son de cuantización aproximada (Q4). Ollama puede variar un poco. El enjambre **no carga dos copias del mismo modelo**: coordinador y programador comparten uno y hacen cola. Dos modelos distintos solo corren a la vez si la suma cabe en el tope.

| Mac | Preset | Modelos distintos | Tope |
| --- | --- | --- | --- |
| MacBook Pro 24 GB | `pro-24` | `qwen2.5-coder:14b` (9 GB, coordinador y programador), `qwen2.5:7b` (4,7 GB, escritor y archivos), `qwen2.5vl:3b` (3,2 GB, ojos) | 17 GB |
| Mac mini M4 16 GB | `mini-16` | `qwen2.5-coder:7b` (4,7 GB, compartido), `llama3.2:3b` (2 GB), `qwen2.5:1.5b` (1,1 GB), `moondream` (1,8 GB) | 11 GB |

Suma aproximada si estuvieran todos residentes: unos 16,9 GB en el Pro y 9,6 GB en el mini. En 16 GB de RAM el sistema también necesita memoria; si notas intercambio, baja `hardware.presupuesto_gb` a `8`.

Sin red, Investigador y las webs (ChatGPT, Claude, Muse, navegador) se quedan en el ancla, con la etiqueta **sin red**. El trabajo lo siguen los locales. Al volver la red, reaparecen. Antigravity está marcado como app local: se intenta igual; si su propia nube no responde, el enjambre sigue sin ella.

## Instalación en el MacBook Pro o en el mini

1. Instala las herramientas de Xcode si `swift` no existe:

   ```bash
   xcode-select --install
   ```

2. Instala Ollama y, en una terminal, déjalo en marcha (`ollama serve` si no arranca solo).

3. En esta carpeta:

   ```bash
   bash scripts/configurar.sh
   ```

   Compila, firma el `.app` en local y copia la configuración a `~/Library/Application Support/Enjambre/` solo si aún no existe.

4. Descarga los modelos del preset de esa máquina (varios gigabytes; hace falta red solo esta vez):

   ```bash
   bash scripts/descargar-modelos.sh
   ```

5. Mira los cursores sin esperar a los modelos:

   ```bash
   open "build/Enjambre de Agentes.app" --args --demo
   ```

6. Para usarlo de verdad, abre la app sin `--demo`. Queda en la barra de menú, sin icono en el Dock.

Si Gatekeeper se queja de una app descargada, clic derecho → Abrir, o `xattr -dr com.apple.quarantine` sobre el `.app` que tú mismo compilaste.

## Permisos

La primera vez macOS pide:

| Permiso | Para qué | Dónde |
| --- | --- | --- |
| Accesibilidad | Leer y pulsar la interfaz de otras apps | Ajustes → Privacidad y seguridad → Accesibilidad |
| Grabación de pantalla | Capturas y OCR si Accesibilidad no devuelve texto | Privacidad → Grabación de pantalla |
| Micrófono y reconocimiento de voz | La orden hablada | Al pulsar Hablar |
| Automatización | AppleScript sobre Finder, Safari, etc. | El sistema lo pregunta en el primer uso |

La parada con `⌃⌥⌘K` no depende de Accesibilidad: es un atajo global. El botón **Parar todo** de la barra tampoco.

Desde el menú contextual del icono (clic derecho) está **Permisos…**, que vuelve a pedir Accesibilidad y grabación y abre Ajustes.

## Cómo se usa

- Clic en el icono, escribes la orden y **Ejecutar**. Atajo: `⌃⌥⌘E`.
- **Hablar** o `⌃⌥⌘Espacio`. Otra vez para cerrar el micrófono. La frase entra al chat.
- **Chat** abre la ventana del grupo. Ahí ves el debate, escribes, `@mencionas`, y pulsas **Aprobar** o **Vetar**.
- Con la política `si-destructivo` (la de fábrica) el plan se ejecuta solo si no borra, no envía y no compra, y si no hubo sugerencias de fuera. Si las hubo, o si el plan es delicado, espera tu sí. Si no respondes a tiempo, no hace nada.
- **Demo** repite la animación y unas líneas de debate de mentira.

Una orden de ejemplo: «crea en el Escritorio un archivo notas.txt que diga hola y resume en una frase qué hiciste».

## Apps de chat (como una persona)

`config/adaptadores.yaml` describe cada app. Para añadir otra, copia un bloque. No hace falta recompilar.

Campos útiles: `aplicacion`, `url`, `navegador`, `rol_entrada` (por ejemplo `AXTextArea`), `pista_entrada`, `tecla_enviar`, `rol_respuesta`, `requiere_red`. El Inspector de Accesibilidad (Xcode → Open Developer Tool → Accessibility Inspector) te dice el rol real del cuadro de texto si el de fábrica no acierta. Los nombres de ventana de Antigravity, ChatGPT y Claude cambian entre versiones: trátalos como punto de partida, no como contrato.

El agente pide `operar_chat` con `adaptador` y `texto`. El cursor del overlay se va al campo. Escribir por Accesibilidad no mueve el ratón físico y puede ocurrir en paralelo en **apps distintas**. El teclado y el ratón reales van de uno en uno.

Si el texto de la pantalla parece un captcha («no soy un robot», «verify you are human»), el agente se detiene y te lo dice. Igual si el campo es de contraseña.

## Los dos Mac en la misma red

No hay panel web. El mini puede prestar modelos por un puerto TCP (47831) con un token compartido. Las herramientas (shell, ratón, apps) siguen en el Mac que recibió la orden, que es donde estás mirando.

En el **Mac mini** (`~/Library/Application Support/Enjambre/enjambre.yaml`):

```yaml
nodo:
  rol: trabajador
  nombre: mini
  puerto: 47831
  token: "un-secreto-largo-que-eliges-tu"
```

En el **MacBook**:

```yaml
nodo:
  rol: anfitrion
  token: "el-mismo-secreto"
nodos:
  - nombre: mini
    host: "192.168.1.40"   # o mini.local
    puerto: 47831
```

Un agente con `nodo: mini` y `modalidad: local` manda la inferencia al mini. Si el mini no responde, esa tarea vuelve a un agente de esta máquina. El token se compara en cada mensaje. Sin token, el trabajador no arranca. El mini no acepta órdenes de shell por ese puerto: solo completa texto de modelo.

## Telegram y agentes de fuera

1. Creas un bot con BotFather y pones el token en `telegram.token`.
2. `telegram.activo: true`.
3. Escribes al bot `/id`. El registro anota el chat id (también te lo contesta). Lo pones en `telegram.chat_ids`. Hasta entonces no acepta órdenes.
4. Un mensaje privado de un chat autorizado es una orden. `/parar`, `/demo`, `/estado`, `/ayuda`.
5. `telegram.chat_grupo` es un grupo. El enjambre copia ahí el chat. Lo que se escriba en el grupo entra como **sugerencia**, no como orden. Así puede participar un bot de Grok que lea ese grupo.

El webhook es aparte, y viene apagado:

```yaml
webhook:
  activo: true
  secreto: "otro-secreto-largo"
  puerto: 8765
  exponer_lan: false   # true solo si aceptas que escuche en la red local
  url_salida: ""       # si lo rellenas, cada mensaje del chat se reenvía con la misma firma
```

No hay página. Solo JSON.

- `POST /v1/mensajes` con cuerpo `{"autor":"Grok","texto":"..."}` y cabecera `X-Enjambre-Firma` = HMAC-SHA256 del cuerpo en hexadecimal, clave el secreto.
- `GET /v1/mensajes` con `X-Enjambre-Tiempo` (unix, ±60 s) y `X-Enjambre-Firma` = HMAC de `ruta + salto de línea + tiempo`.

Una sugerencia queda en el chat con etiqueta naranja. El coordinador puede tenerla en cuenta al fusionar el plan, y si hubo alguna el plan espera tu aprobación. Nadie lanza herramientas a partir del POST.

Ejemplo de firma (el mismo algoritmo está cubierto por las pruebas):

```bash
SECRETO="otro-secreto-largo"
CUERPO='{"autor":"Grok","texto":"yo miraría el borde"}'
FIRMA=$(printf '%s' "$CUERPO" | openssl dgst -sha256 -hmac "$SECRETO" | awk '{print $2}')
curl -s -X POST "http://127.0.0.1:8765/v1/mensajes" \
  -H "X-Enjambre-Firma: $FIRMA" \
  -H "Content-Type: application/json" \
  -d "$CUERPO"
```

## Parada

- `⌃⌥⌘K`
- Botón **Parar todo**
- En Telegram, `/parar`
- En otra terminal, `enjambre parar` (avisa a la app que ya está abierta)

Eso mata los procesos que el enjambre lanzó y corta el turno. Una orden nueva puede empezar después.

## Coste, con honestidad

- Ollama en tu Mac: disco y electricidad. No hay factura de API. Un coder de 14B son unos 9 GB de descarga; el preset del Pro se acerca a 17 GB entre los tres modelos.
- Claude Code: límites de tu suscripción, no tokens de la API, y solo si el Investigador llega a usarlo.
- OpenAI, Gemini, Grok, OpenRouter: lo que cobre cada uno, y solo si pones la clave.
- Las apps de chat gastan lo que ya pagas en esas cuentas.
- La demo no llama a nadie.

Cada paso de un agente es una llamada al modelo. `cerebro.max_pasos` está en 6 y `max_paralelo` en 2 para no disparar ni la RAM ni, si usas nube, la cuota. El debate añade una vuelta por participante y una fusión.

## Desarrollo

```bash
swift test
```

En Linux (o en CI) eso cubre el núcleo: configuración, presets, cola de RAM, seguridad del shell, debate y reasignación sin red, firma HMAC, nodo TCP, Telegram y un orquestador con respuestas guionizadas. No levanta la ventana.

En el Mac, `swift build` y `bash scripts/empaquetar.sh` generan el `.app`. El flujo de GitHub incluye un job `macos-14` para compilar la interfaz.

## Qué está verificado y qué no

Verificado aquí, con `swift test` (16 pruebas): presets de 24 y 16 GB y que la suma de modelos distintos no pasa el tope; la cola que no arranca dos modelos si no caben; el rechazo de borrados catastróficos y la confirmación de `rm` normal; el plan y el orquestador con un cerebro falso; la firma HMAC-SHA256; el nodo que solo completa texto; las sugerencias marcadas como tales; los adaptadores fusionados desde YAML.

No verificado en esta máquina, porque no es un Mac: la ventana, los permisos de Accesibilidad, el OCR, la voz, Ollama de verdad, los selectores AX de Antigravity / ChatGPT / Claude / Muse, y el monitor de red. Esos caminos están escritos y el job de macOS del repositorio es el que puede compilarlos. Si un cuadro de texto no se encuentra, se corrige en `adaptadores.yaml`, no hace falta tocar el código.

## Licencia

MIT. Ver `LICENSE`.
