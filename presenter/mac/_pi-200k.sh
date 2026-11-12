#!/usr/bin/env bash
# Shared by 2-pi-200k.sh and 4-pi-200k.sh: restore the prewarmed slot, then open Pi on the matching session.
# Pi must run with cwd = $WS: the session was built there, and Pi puts the cwd into its system prompt.
# Any difference in the prefix means a full re-read of ~200k tokens (about 51 min on the Mac).
set -eu
MODEL=$1; EXPECT=$2
WS=${WS:-$HOME/workshop}; PORT=${PORT:-8080}; URL=http://127.0.0.1:$PORT
SLOT=$MODEL-200k.bin; SESSION=$WS/sessions/$MODEL-200k.jsonl
cd "$WS"
curl -sf "$URL/health" >/dev/null || { echo "Сервер не отвечает на $URL. Сначала запусти его в окне 0."; exit 3; }
curl -sf "$URL/v1/models" | grep -q "$EXPECT" || { echo "На сервере не $EXPECT. Останови его (Ctrl-C в окне 0) и запусти нужный."; exit 3; }
[ -s "slots/$SLOT" ] || { echo "Нет файла slots/$SLOT."; exit 3; }
[ -s "$SESSION" ] || { echo "Нет сессии $SESSION."; exit 3; }
if [ -f "$SESSION.bak" ] && ! cmp -s "$SESSION" "$SESSION.bak"; then
  echo "Сессия уже менялась после прогрева (в ней есть вопросы с прошлого запуска), и слот к ней не подойдёт."
  printf 'Enter — вернуть чистую сессию из .bak, Ctrl-C — отмена '; read -r _
  cp -p "$SESSION.bak" "$SESSION"; echo "Чистая сессия восстановлена."
fi
python3 ws.py restore --server "$URL" --slot-file "$SLOT"
printf 'Enter — открыть Pi '; read -r _
exec pi --provider ws-mac --model "$MODEL" --session "$SESSION"
