#!/bin/bash
# Construye un .dmg para arrastrar Enjambre de Agentes a Aplicaciones.
# Firma ad hoc si no hay certificado. Con CODESIGN_IDENTITY (Developer ID) queda listo para notarizar.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname)" != "Darwin" ]]; then
  echo "crear-dmg.sh solo corre en macOS."
  exit 1
fi

VERSION="$(grep -m1 'versionEnjambre' Sources/EnjambreNucleo/Version.swift | sed -E 's/.*"([^"]+)".*/\1/')"
IDENTIDAD="${CODESIGN_IDENTITY:--}"
if [[ -z "$IDENTIDAD" ]]; then IDENTIDAD="-"; fi
mkdir -p build
BINARIOS=()

compilar() {
  local triple="$1"
  echo "Compilando ${triple}…"
  if swift build -c release --triple "$triple"; then
    local ruta
    ruta="$(swift build -c release --triple "$triple" --show-bin-path)/Enjambre"
    if [[ -x "$ruta" ]]; then
      BINARIOS+=("$ruta")
    fi
  else
    echo "No se pudo compilar ${triple}; sigo con las arquitecturas disponibles."
  fi
}

compilar "arm64-apple-macosx14.0"
compilar "x86_64-apple-macosx14.0"

if [[ ${#BINARIOS[@]} -eq 0 ]]; then
  echo "Compilando para la arquitectura de esta máquina…"
  swift build -c release
  BINARIOS+=("$(swift build -c release --show-bin-path)/Enjambre")
fi

UNIVERSAL="build/Enjambre"
if [[ ${#BINARIOS[@]} -gt 1 ]]; then
  lipo -create "${BINARIOS[@]}" -output "$UNIVERSAL"
else
  cp "${BINARIOS[0]}" "$UNIVERSAL"
fi
chmod +x "$UNIVERSAL"

APP="build/Enjambre de Agentes.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$UNIVERSAL" "$APP/Contents/MacOS/Enjambre"
cp Recursos/Info.plist "$APP/Contents/Info.plist"
cp config/enjambre.yaml config/adaptadores.yaml "$APP/Contents/Resources/"
# Firma lista para un Developer ID. Sin certificado, la firma ad hoc permite al sistema recordar los permisos.
if [[ "$IDENTIDAD" == "-" ]]; then
  codesign --force --deep --sign - "$APP"
else
  codesign --force --deep --options runtime --timestamp --sign "$IDENTIDAD" "$APP"
fi

VOL="Enjambre de Agentes"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="build/Enjambre-de-Agentes-${VERSION}.dmg"
rm -f "$DMG"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Disco listo: $DMG"
lipo -info "$APP/Contents/MacOS/Enjambre" || true
