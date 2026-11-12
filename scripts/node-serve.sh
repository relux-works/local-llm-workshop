#!/usr/bin/env bash
# llama-server on the GPU node, same build (b12317) and flags as the Mac. Logs to /root/ws/logs/server-<mode>.log.
# Usage: node-serve.sh q27b            one slot, 262,144 tokens (fills slots for the Mac)
#        node-serve.sh flashnext       one slot, 262,144 tokens (fills slots for the Mac)
#        node-serve.sh flashnext-par N N parallel slots of 131,072 tokens (the cloud act)
set -eu
W=/root/ws; BIN=$(dirname "$(find $W/bin -name llama-server -type f | head -1)")
export LD_LIBRARY_PATH=$BIN:${LD_LIBRARY_PATH:-}
FN=$W/models/Qwen3.8-Flash-Next-UD-IQ4_XS-00001-of-00004.gguf
case "$1" in
  q27b)          M=$W/models/Qwen3.8-27B-Q4_K_M.gguf; A=(-c 262144 -np 1) ;;
  flashnext)     M=$FN; A=(-c 262144 -np 1) ;;
  flashnext-par) N=${2:-6}; M=$FN; A=(-c $((131072*N)) -np $N) ;;
  *) echo "usage: $0 q27b|flashnext|flashnext-par N"; exit 2 ;;
esac
mkdir -p $W/slots $W/logs
nohup $BIN/llama-server -m "$M" "${A[@]}" -ngl 999 -fa on -ctk q8_0 -ctv q8_0 --jinja --host 127.0.0.1 --port 8080 \
  --slot-save-path $W/slots --metrics > $W/logs/server-$1.log 2>&1 &
echo "llama-server pid $! ($1)"; echo $! > $W/server.pid
for i in $(seq 120); do curl -sf http://127.0.0.1:8080/health >/dev/null && { echo "ready after ${i}x2 s"; exit 0; }; sleep 2; done
echo "not ready after 240 s"; tail -20 $W/logs/server-$1.log; exit 1
