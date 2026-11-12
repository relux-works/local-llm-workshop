#!/usr/bin/env bash
# Acceptance check on the Mac: restore the slot into the local llama-server and ask through the captured request.
# Pass: prompt_n is about the length of the question (tens of tokens), not ~200k. Usage: check-session.sh qwen27b|flashnext
set -eu
MODEL=${1:-qwen27b}; WS=${WS:-$HOME/workshop}; cd "$WS"
python3 ws.py ask --server http://127.0.0.1:8080 --req "cap/$MODEL-200k" --slot-file "$MODEL-200k.bin"
echo "Restoring again so the demo starts from the clean slot:"
python3 ws.py restore --server http://127.0.0.1:8080 --slot-file "$MODEL-200k.bin"
