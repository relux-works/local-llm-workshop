#!/usr/bin/env bash
# One more thing: hybrid inference, live. Pi on the Mac starts a NEW ~50k-token session; the cloud GPU reads it and
# saves the exact prefix of Pi's next request into a slot file; the Mac downloads the file, restores it, and Pi
# continues locally. Window 1 of the MBP, with Flash-Next already serving in window 0 (./4-flash.sh).
# Needs ~/workshop/node.env (NODE_HOST, NODE_PORT, optional SSH_EXTRA) and the node running Flash-Next.
set -eu
WS=${WS:-$HOME/workshop}; PORT=${PORT:-8080}; URL=http://127.0.0.1:$PORT
TPORT=${TPORT:-18080}; CPORT=${CPORT:-18091}; NODE=http://127.0.0.1:$TPORT
MODEL=flashnext; EXPECT=Flash-Next; CTX=${CTX:-ctx/ctx50k.md}
cd "$WS"
[ -f node.env ] || { echo "Нет $WS/node.env с адресом узла."; exit 3; }
. ./node.env
: "${NODE_HOST:?NODE_HOST в node.env}" "${NODE_PORT:?NODE_PORT в node.env}"
KEY=${KEY:-$HOME/.ssh/id_ed25519_workshop}
SSHO=(-i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 -p "$NODE_PORT")
[ -n "${SSH_EXTRA:-}" ] && SSHO+=($SSH_EXTRA)
# BIND_IF (e.g. the 5G interface): used only while it has an address, so a dropped hotspot falls back to the default route.
if [ -n "${BIND_IF:-}" ]; then
  if ifconfig "$BIND_IF" 2>/dev/null | grep -q 'inet '; then SSHO+=(-o "BindInterface=$BIND_IF"); echo "Канал к узлу: $BIND_IF."
  else echo "Интерфейс $BIND_IF не активен, иду к узлу по маршруту по умолчанию."; fi
fi
now() { python3 -c 'import time; print("%.1f" % time.time())'; }
dt() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.1f", b - a }'; }
busy() { curl -s -m 1 "http://127.0.0.1:$1/" >/dev/null 2>&1; }

# Guards: Flash-Next on the Mac, the context file, free local ports.
curl -sf "$URL/health" >/dev/null || { echo "Сервер на Маке не отвечает. Запусти ./4-flash.sh в окне 0."; exit 3; }
curl -sf "$URL/v1/models" | grep -q "$EXPECT" || { echo "На Маке не $EXPECT. Останови сервер (Ctrl-C в окне 0) и запусти ./4-flash.sh."; exit 3; }
[ -s "$CTX" ] || { echo "Нет файла $CTX."; exit 3; }
for p in "$TPORT" "$CPORT"; do busy "$p" && { echo "Порт $p занят (остался прошлый запуск?). Освободи его и запусти снова."; exit 3; }; done

ID=$(date -u +%H%M%S); NAME=hybrid-$ID; SESSION=$WS/sessions/$NAME.jsonl
mkdir -p sessions "cap/$NAME" slots logs
ssh "${SSHO[@]}" -N -o ExitOnForwardFailure=yes -L "$TPORT:127.0.0.1:8080" root@"$NODE_HOST" & TUN=$!
CAP=
trap 'kill $TUN 2>/dev/null || true; [ -n "$CAP" ] && kill $CAP 2>/dev/null || true' EXIT
for _ in $(seq 30); do curl -sf "$NODE/health" >/dev/null && break; sleep 1; done
curl -sf "$NODE/health" >/dev/null || { echo "Узел не отвечает через туннель."; exit 3; }
curl -sf "$NODE/v1/models" | grep -q "$EXPECT" || { echo "На узле не $EXPECT."; exit 3; }
NTOK=$(python3 -c 'import json,sys,urllib.request
c=open(sys.argv[2]).read()
r=urllib.request.Request(sys.argv[1]+"/tokenize",data=json.dumps({"content":c}).encode(),headers={"Content-Type":"application/json"})
print(len(json.load(urllib.request.urlopen(r))["tokens"]))' "$NODE" "$CTX")
echo "Новая сессия $NAME: $((NTOK/1000)) тыс. токенов исходников llama.cpp ($CTX)."

echo; echo "== 1. Pi отправляет контекст в облако; облако читает его и отвечает"
T0=$(now)
pi --provider ws-node --model "$MODEL" --session "$SESSION" -p "@$CTX" \
  "Это исходники сервера llama.cpp: задачи, очередь и общие типы. Инструменты не вызывай, отвечай только по этому тексту. В пяти строках: как запрос проходит путь от HTTP до слота?" \
  </dev/null | tee "logs/$NAME-build.txt"
T1=$(now); echo "-- облако прочитало и ответило за $(dt "$T0" "$T1") с"

echo; echo "== 2. Облако сохраняет состояние ровно до следующего вопроса"
cp "$SESSION" "sessions/$NAME-probe.jsonl"
python3 ws.py capture --listen "$CPORT" --out "cap/$NAME" >/dev/null & CAP=$!
for _ in $(seq 20); do busy "$CPORT" && break; sleep 0.2; done
pi --provider ws-capture --model "$MODEL" --session "$WS/sessions/$NAME-probe.jsonl" -p "ping" </dev/null >/dev/null
kill $CAP 2>/dev/null || true; CAP=; rm -f "sessions/$NAME-probe.jsonl"
SLOT=$(curl -sf "$NODE/slots" | python3 -c 'import json,sys
free=[s["id"] for s in json.load(sys.stdin) if not s.get("is_processing")]
print(max(free) if free else "")')
[ -n "$SLOT" ] || { echo "На узле нет свободного слота: все заняты. Подожди, пока допишутся лендинги, и запусти снова."; exit 3; }
T2=$(now)
python3 ws.py warm --server "$NODE" --req "cap/$NAME" --slot-file "$NAME.bin" --slot "$SLOT"
T3=$(now); echo "-- состояние готово за $(dt "$T2" "$T3") с"

echo; echo "== 3. Скачиваем состояние на Мак"
rsync -P -e "ssh ${SSHO[*]}" root@"$NODE_HOST":/root/ws/slots/"$NAME.bin" slots/
T4=$(now)
GB=$(python3 -c 'import os,sys; print("%.2f" % (os.path.getsize(sys.argv[1])/1e9))' "slots/$NAME.bin")
echo "-- $GB ГБ за $(dt "$T3" "$T4") с"
kill $TUN 2>/dev/null || true

echo; echo "== 4. Мак поднимает состояние"
python3 ws.py restore --server "$URL" --slot-file "$NAME.bin"
T5=$(now)

echo
echo "Итого: облако $(dt "$T0" "$T3") с, скачивание $(dt "$T3" "$T4") с ($GB ГБ), подъём на Маке $(dt "$T4" "$T5") с."
printf 'Enter — открыть Pi на этой сессии '; read -r _
exec pi --provider ws-mac --model "$MODEL" --session "$SESSION"
