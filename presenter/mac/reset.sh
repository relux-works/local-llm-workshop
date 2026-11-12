#!/usr/bin/env bash
# After a rehearsal: stop the server, put the prewarmed sessions back from .bak, remove the act 1 scratch folder.
# Never touches slots/, models/ or bin/.
set -eu
WS=${WS:-$HOME/workshop}; cd "$WS"
"$WS/stop.sh" || echo "Сервер не остановлен — см. сообщение выше."
for B in sessions/*.jsonl.bak; do
  [ -f "$B" ] || continue
  F=${B%.bak}
  if cmp -s "$F" "$B"; then echo "Сессия $F чистая."; else cp -p "$B" "$F"; echo "Сессия $F восстановлена из .bak."; fi
done
if [ -d "$WS/play" ]; then rm -rf -- "$WS/play"; echo "Папка play/ удалена."; fi
echo "Готово: можно начинать с ./0-check.sh"
