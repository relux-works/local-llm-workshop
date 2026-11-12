#!/usr/bin/env bash
# Stop the llama-server that listens on the workshop port. Kills that PID only, and only if it is llama-server.
set -eu
PORT=${PORT:-8080}
PIDS=$(lsof -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | sort -u || true)
if [ -z "$PIDS" ]; then
  LOADING=$(pgrep -x llama-server | tr '\n' ' ' || true)
  if [ -n "$LOADING" ]; then
    echo "На порту $PORT никто не слушает, но llama-server есть (PID $LOADING): грузится или завис."
    echo "Ctrl-C в его окне или kill $LOADING"; exit 3
  fi
  echo "Сервер не запущен, порт $PORT свободен."; exit 0
fi
for P in $PIDS; do
  C=$(ps -o comm= -p "$P" || true)
  case "$C" in
    *llama-server) ;;
    *) echo "Порт $PORT держит не llama-server (PID $P: $C). Не трогаю."; exit 3 ;;
  esac
done
for P in $PIDS; do kill "$P"; done
for _ in $(seq 30); do
  ALIVE=; for P in $PIDS; do kill -0 "$P" 2>/dev/null && ALIVE=1; done
  [ -z "$ALIVE" ] && { echo "Сервер остановлен (PID $PIDS), порт $PORT свободен."; exit 0; }
  sleep 0.5
done
echo "Сервер (PID $PIDS) не остановился за 15 с. kill -9 $PIDS"; exit 1
