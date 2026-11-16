#!/bin/bash
# Descarga los modelos del preset que corresponde a la RAM de este Mac.
set -euo pipefail
if [[ "$(uname)" != "Darwin" ]]; then
  echo "Este script es para los Mac del usuario."
  exit 1
fi
if ! command -v ollama >/dev/null 2>&1; then
  echo "Instala Ollama desde https://ollama.com y vuelve a correr este script."
  exit 1
fi
BYTES="$(sysctl -n hw.memsize)"
GB=$(( BYTES / 1024 / 1024 / 1024 ))
echo "RAM detectada: ${GB} GB"
if [[ "$GB" -ge 20 ]]; then
  echo "Preset pro-24. Descarga aproximada: 9 + 4,7 + 3,2 GB."
  ollama pull qwen2.5-coder:14b
  ollama pull qwen2.5:7b
  ollama pull qwen2.5vl:3b
else
  echo "Preset mini-16. Descarga aproximada: 4,7 + 2 + 1,1 + 1,8 GB."
  ollama pull qwen2.5-coder:7b
  ollama pull llama3.2:3b
  ollama pull qwen2.5:1.5b
  ollama pull moondream
fi
echo "Modelos listos. Ollama los carga de uno en uno; el enjambre no los pide todos a la vez si no caben."
