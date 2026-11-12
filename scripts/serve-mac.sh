#!/usr/bin/env bash
# llama-server on the MacBook Pro with the same build and flags as the GPU node, so slot files move between them.
# Run it from an interactive shell or tmux (normal priority, PRI 31), never from a background daemon.
# Usage: serve-mac.sh q27b | q27b-512k | flashnext
set -eu
WS=${WS:-$HOME/workshop}; PORT=${PORT:-8080}; MODE=${1:-q27b}
# bin/current (set by build-llama.sh --use) wins; otherwise the pinned prebuilt release.
if [ -x "$WS/bin/current/llama-server" ]; then BIN=$WS/bin/current; else BIN=$WS/bin/llama-b12317; fi
case "$MODE" in
  q27b)      M=$WS/models/Qwen3.8-27B-Q4_K_M.gguf; C=262144; EXTRA=() ;;
  q27b-512k) M=$WS/models/Qwen3.8-27B-Q4_K_M.gguf; C=524288; EXTRA=(--rope-scaling yarn --rope-scale 2 --yarn-orig-ctx 262144) ;;
  flashnext) M=$WS/models/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00004.gguf; C=262144; EXTRA=() ;;
  *) echo "usage: $0 q27b|q27b-512k|flashnext"; exit 2 ;;
esac
# One model at a time: refuse while another server listens on the port or is still loading.
BUSY=$( { lsof -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true; pgrep -x llama-server || true; } | sort -u | tr '\n' ' ')
if [ -n "${BUSY// /}" ]; then
  echo "Сервер уже работает (PID $BUSY). Останови его: Ctrl-C в окне, где он запущен, или ./stop.sh"; exit 3
fi
mkdir -p "$WS/slots" "$WS/logs"
set -x
"$BIN/llama-server" -m "$M" -c $C -np 1 -ngl 999 -fa on -ctk q8_0 -ctv q8_0 --jinja \
  --host 127.0.0.1 --port "$PORT" --slot-save-path "$WS/slots" --metrics ${EXTRA[@]+"${EXTRA[@]}"} 2>&1 | tee "$WS/logs/server-$MODE.log"
