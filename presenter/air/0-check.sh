#!/usr/bin/env bash
# Read-only preflight on the presenter's laptop: the tunnel, the model on the node, the tools, an empty sites/.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); URL=${URL:-http://127.0.0.1:8081}
FAIL=0
ok()  { printf '  ok   %s\n' "$*"; }
bad() { printf '  НЕТ  %s\n' "$*"; FAIL=1; }
echo "Проверка Air ($HERE):"
if curl -sf -m 5 "$URL/health" >/dev/null; then
  ok "туннель и сервер на узле отвечают ($URL)"
  if curl -sf -m 5 "$URL/v1/models" | grep -q "Flash-Next"; then ok "на узле Qwen3.8-Flash-Next"; else bad "на узле не Flash-Next"; fi
  N=$(curl -sf -m 5 "$URL/slots" | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo "?")
  ok "слотов на узле: $N (для четырёх лендингов нужно не меньше 4)"
else
  bad "туннель не отвечает — запусти ./0-tunnel.sh в отдельной вкладке"
fi
if V=$(pi --version 2>/dev/null); then ok "pi $V"; else bad "pi не найден"; fi
if V=$(tmux -V 2>/dev/null); then ok "$V"; else bad "tmux не найден"; fi
if [ -z "$(ls -A "$HERE/sites" 2>/dev/null)" ]; then ok "папка sites/ пустая"; else bad "в sites/ остались страницы — ./reset.sh"; fi
if [ -d "$HERE/sites-backup" ]; then ok "запасные страницы на месте (sites-backup/)"; else bad "нет sites-backup/"; fi
if [ $FAIL = 0 ]; then echo "Всё готово."; else echo "Есть пункты НЕТ — см. выше."; fi
exit $FAIL
