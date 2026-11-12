#!/usr/bin/env bash
# Read-only preflight on the MacBook Pro before the workshop. Changes nothing.
set -u
WS=${WS:-$HOME/workshop}; PORT=${PORT:-8080}; cd "$WS" || exit 3
FAIL=0
ok()  { printf '  ok   %s\n' "$*"; }
bad() { printf '  НЕТ  %s\n' "$*"; FAIL=1; }
gb()  { ls -lL "$1" | awk '{printf "%.2f ГБ", $5/1e9}'; }
echo "Проверка MBP ($WS):"
P=$( { lsof -t -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true; pgrep -x llama-server || true; } | sort -u | tr '\n' ' ')
if [ -z "${P// /}" ]; then ok "сервер не запущен, порт $PORT свободен"; else bad "сервер уже работает (PID $P) — ./stop.sh"; fi
for S in qwen27b-200k.bin flashnext-200k.bin; do
  if [ -s "slots/$S" ]; then ok "слот $S, $(gb "slots/$S")"; else bad "нет слота slots/$S"; fi
done
for B in sessions/*.jsonl.bak; do
  [ -f "$B" ] || continue
  F=${B%.bak}
  if cmp -s "$F" "$B"; then ok "сессия $F чистая"; else bad "сессия $F изменена — ./reset.sh"; fi
done
for M in models/*; do
  [ -e "$M" ] || { bad "$M: не найден (LaCie подключён?)"; continue; }
  if [ "$(head -c 4 "$M" 2>/dev/null)" = GGUF ]; then ok "модель $(basename "$M"), $(gb "$M")"; else bad "$M не читается (LaCie, доступ к диску?)"; fi
done
if command -v pmset >/dev/null; then
  if pmset -g batt | grep -q "AC Power"; then ok "питание от сети"; else bad "работает от батареи — подключи питание"; fi
fi
ok "свободно на диске: $(df -h / | awk 'NR==2{print $4}')"
if V=$(pi --version 2>/dev/null); then ok "pi $V"; else bad "pi не найден"; fi
if pgrep -x caffeinate >/dev/null; then ok "caffeinate работает"; else bad "caffeinate не запущен — caffeinate -dimsu &"; fi
if [ $FAIL = 0 ]; then echo "Всё готово, едем дальше: ./1-qwen.sh"; else echo "Есть пункты НЕТ — см. выше."; fi
exit $FAIL
