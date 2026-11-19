#!/bin/bash
# Construye Enjambre de Agentes.app a partir del binario de SwiftPM.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname)" != "Darwin" ]]; then
  echo "empaquetar.sh solo corre en macOS."
  exit 1
fi
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Enjambre"
APP="build/Enjambre de Agentes.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Enjambre"
cp Recursos/Info.plist "$APP/Contents/Info.plist"
cp config/enjambre.yaml config/adaptadores.yaml "$APP/Contents/Resources/"
chmod +x "$APP/Contents/MacOS/Enjambre"
codesign --force --deep --sign - "$APP"
echo "Listo: $APP"
