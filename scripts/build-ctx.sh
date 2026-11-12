#!/usr/bin/env bash
# Build a context file from llama.cpp b12317 server and memory sources, one fenced block per file.
#   build-ctx.sh 200k   ~200k tokens: the whole server plus the recurrent and hybrid memory (acts 2 and 4)
#   build-ctx.sh 50k    ~51k tokens: tasks, queue and common types (the live hybrid demo, 6-hybrid.sh)
# Usage: build-ctx.sh 200k|50k [llama.cpp source dir] [output]
set -eu
SIZE=${1:?usage: $0 200k|50k [src] [out]}; L=${2:-llama.cpp-b12317}; OUT=${3:-ctx$SIZE.md}
case "$SIZE" in
  200k) TITLE="исходники сервера и памяти состояний"
        FILES="tools/server/server.cpp tools/server/server-context.h tools/server/server-context.cpp tools/server/server-task.h
tools/server/server-task.cpp tools/server/server-queue.h tools/server/server-queue.cpp tools/server/server-common.h
tools/server/server-http.cpp src/llama-memory-recurrent.cpp src/llama-memory-hybrid.cpp src/llama-context.cpp" ;;
  50k)  TITLE="сервер — задачи, очередь, общие типы"
        FILES="tools/server/server.cpp tools/server/server-context.h tools/server/server-task.h tools/server/server-task.cpp
tools/server/server-queue.h tools/server/server-queue.cpp tools/server/server-common.h src/llama-memory-hybrid.cpp" ;;
  *) echo "usage: $0 200k|50k [src] [out]"; exit 2 ;;
esac
{
  echo "# llama.cpp b12317 (e0949d09): $TITLE"
  echo
  for f in $FILES; do echo "## $f"; echo; echo '```cpp'; cat "$L/$f"; echo '```'; echo; done
} > "$OUT"
wc -c "$OUT"
