#!/usr/bin/env bash
# Act 1, window 1: wait for the server, show its scheduling priority, then open Pi in a scratch folder (play/).
set -eu
WS=${WS:-$HOME/workshop}; PORT=${PORT:-8080}; URL=http://127.0.0.1:$PORT
echo "Жду сервер на $URL ..."
for _ in $(seq 120); do curl -sf "$URL/health" >/dev/null && break; sleep 1; done
curl -sf "$URL/health" >/dev/null || { echo "Сервер не отвечает. Запусти ./1-qwen.sh в окне 0."; exit 3; }
curl -sf "$URL/v1/models" | grep -q "Qwen3.8-27B" || { echo "На сервере не Qwen3.8-27B. Останови его и запусти ./1-qwen.sh."; exit 3; }
PID=$(lsof -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -1)
read -r PRI NICE <<<"$(ps -o pri=,nice= -p "$PID")"
if [ "$NICE" = 0 ] && [ "$PRI" -ge 31 ]; then
  echo "Приоритет сервера: pri $PRI, nice $NICE — обычный, macOS его не притормаживает."
else
  echo "ВНИМАНИЕ: pri $PRI, nice $NICE — фоновый класс, генерация будет в разы медленнее."
  echo "Перезапусти сервер из терминала или tmux: Ctrl-C в окне 0, затем ./1-qwen.sh."
fi
mkdir -p "$WS/play"; cd "$WS/play"
printf 'Enter — открыть Pi (папка play/) '; read -r _
exec pi --provider ws-mac --model qwen27b
