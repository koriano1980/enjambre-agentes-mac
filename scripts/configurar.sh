#!/bin/bash
# Un solo comando en el MacBook Pro o en el Mac mini.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname)" != "Darwin" ]]; then
  echo "configurar.sh prepara la app en macOS."
  echo "En esta máquina solo puedes comprobar el núcleo: swift test"
  exit 1
fi
if ! command -v swift >/dev/null 2>&1; then
  echo "Falta Swift. Instala las herramientas de Xcode:"
  echo "  xcode-select --install"
  exit 1
fi
bash scripts/empaquetar.sh
SOPORTE="$HOME/Library/Application Support/Enjambre"
mkdir -p "$SOPORTE" "$HOME/Library/Logs/Enjambre"
if [[ ! -f "$SOPORTE/enjambre.yaml" ]]; then
  cp config/enjambre.yaml "$SOPORTE/enjambre.yaml"
  cp config/adaptadores.yaml "$SOPORTE/adaptadores.yaml"
  chmod 600 "$SOPORTE/enjambre.yaml"
  echo "Configuración inicial en: $SOPORTE"
else
  echo "Ya existía $SOPORTE/enjambre.yaml; no la pisé."
fi
BYTES="$(sysctl -n hw.memsize)"
GB=$(( BYTES / 1024 / 1024 / 1024 ))
echo
echo "RAM de este Mac: ${GB} GB."
if [[ "$GB" -ge 20 ]]; then
  echo "Se usará el preset pro-24 (coder 14B compartido, trabajador 7B, visión 3B, tope 17 GB)."
else
  echo "Se usará el preset mini-16 (coder 7B compartido, trabajadores 3B y 1.5B, visión pequeña, tope 11 GB)."
fi
echo
echo "Siguiente, si aún no tienes los modelos:"
echo "  bash scripts/descargar-modelos.sh"
echo
echo "Para ver los cursores ahora, sin Ollama ni Claude:"
echo "  open \"build/Enjambre de Agentes.app\" --args --demo"
echo
echo "Permisos la primera vez: Accesibilidad, Grabación de pantalla, Micrófono y, al controlar otra app, Automatización."
echo "Parada inmediata: Control+Opción+Comando+K, o el botón Parar de la barra de menú."
