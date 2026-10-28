#!/usr/bin/env bash
# guardar-key-local.sh: guarda la URL y la key del webhook para el fallback local (cc-local).
# Correlo VOS en una terminal del escritorio del bot. La key se tipea oculta y nunca pasa por el chat.
#   ./guardar-key-local.sh <slug-del-bot>
set -eu
slug=${1:-}
[[ "$slug" =~ ^[a-z0-9][a-z0-9-]{0,39}$ ]] || { echo "uso: $0 <slug-del-bot>  (solo a-z, 0-9 y -)"; exit 1; }
mkdir -p ~/.config/cc-wake/agents && chmod 700 ~/.config/cc-wake ~/.config/cc-wake/agents
umask 077
read -r -p "URL del webhook: " url && printf 'WAKE_URL=%s\n' "$url" > ~/.config/cc-wake/agents/"$slug".env
read -r -s -p "Key del webhook (no se muestra): " key && echo && printf '%s\n' "$key" > ~/.config/cc-wake/agents/"$slug".key
unset key
echo "listo: ~/.config/cc-wake/agents/$slug.env y $slug.key (modo 600)"
