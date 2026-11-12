#!/usr/bin/env bash
# Build a prewarmed ~200k-token Pi session for the Mac. Pi talks to the GPU node through an SSH tunnel; the node
# fills the exact prefix of Pi's next request into a slot and saves it; the Mac downloads the slot file.
# Needs on the node: llama-server with the same model on 127.0.0.1:8080. Usage: build-session.sh qwen27b|flashnext
set -eu
MODEL=${1:-qwen27b}; WS=${WS:-$HOME/workshop}; cd "$WS"
KEY=$HOME/.ssh/id_ed25519_workshop; HOST=${NODE_HOST:?set NODE_HOST}; PORT=${NODE_PORT:?set NODE_PORT}
SSHO=(-i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 -p "$PORT")
NAME=$MODEL-200k
mkdir -p sessions "cap/$NAME" slots logs
ssh "${SSHO[@]}" -N -L 18080:127.0.0.1:8080 root@"$HOST" & TUN=$!
trap 'kill $TUN 2>/dev/null || true' EXIT
for i in $(seq 30); do curl -sf http://127.0.0.1:18080/health >/dev/null && break; sleep 2; done
curl -sf http://127.0.0.1:18080/health; echo " node is up"
case "$MODEL" in qwen27b) EXPECT=Qwen3.8-27B ;; flashnext) EXPECT=Flash-Next ;; esac
curl -sf http://127.0.0.1:18080/v1/models | grep -q "$EXPECT" || { echo "the node runs another model, not $EXPECT: ask the hybrid lane to switch it"; exit 3; }
if [ ! -s "sessions/$NAME.jsonl" ]; then
  echo "== 1. session: the node reads the llama.cpp sources and answers once"
  time pi --provider ws-node --model "$MODEL" --session "$WS/sessions/$NAME.jsonl" -p @ctx/ctx200k.md \
    "Это исходники сервера llama.cpp и его памяти состояний. Инструменты не вызывай, отвечай только по этому тексту. Перечисли главные подсистемы сервера, по строке на каждую." | tee "logs/$NAME-build.txt"
fi
echo "== 2. capture Pi's next request from a copy of the session (the proxy answers 'ok' itself)"
cp "sessions/$NAME.jsonl" "sessions/$NAME-probe.jsonl"
python3 ws.py capture --listen 18091 --out "cap/$NAME" & CAP=$!
sleep 1
pi --provider ws-capture --model "$MODEL" --session "$WS/sessions/$NAME-probe.jsonl" -p "ping" >/dev/null
kill $CAP; rm -f "sessions/$NAME-probe.jsonl"
echo "== 3. the node fills that exact prefix and saves the slot"
python3 ws.py warm --server http://127.0.0.1:18080 --req "cap/$NAME" --slot-file "$NAME.bin"
echo "== 4. download the slot"
rsync -P -e "ssh ${SSHO[*]}" root@"$HOST":/root/ws/slots/"$NAME.bin" slots/
ls -la "slots/$NAME.bin"
