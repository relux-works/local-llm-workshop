#!/usr/bin/env bash
# Optional: build llama.cpp from source at a release tag and install it next to the prebuilt one.
# Policy: we follow llama.cpp main through its release tags (bNNNN). BEHIND=N picks the tag N releases back,
# a buffer against a fresh regression. The workshop itself runs the pinned prebuilt b12317.
# Slot files are tied to the build and the server flags: after switching bin/current, rebuild slots and sessions.
# Usage: build-llama.sh [bNNNN] [--use]     (macOS: Metal; Linux: CUDA when nvcc is on PATH)
set -eu
WS=${WS:-$HOME/workshop}; SRC=${SRC:-$WS/src/llama.cpp}; REPO=${LLAMA_REPO:-https://github.com/ggml-org/llama.cpp}
BEHIND=${BEHIND:-0}; USE=0; TAG=
for A in "$@"; do
  case "$A" in
    --use) USE=1 ;;
    b[0-9]*) TAG=$A ;;
    *) echo "usage: $0 [bNNNN] [--use]"; exit 2 ;;
  esac
done
if [ -d "$SRC/.git" ]; then git -C "$SRC" fetch --quiet --tags origin; else git clone --quiet --filter=blob:none "$REPO" "$SRC"; fi
if [ -z "$TAG" ]; then
  TAG=b$(git -C "$SRC" tag -l 'b[0-9]*' | sed 's/^b//' | grep -E '^[0-9]+$' | sort -n | tail -n $((BEHIND + 1)) | head -1)
fi
git -C "$SRC" rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "нет тега $TAG"; exit 2; }
echo "llama.cpp $TAG ($(git -C "$SRC" rev-parse --short "$TAG^{commit}"))"
[ "${DRY_RUN:-0}" = 1 ] && exit 0
git -C "$SRC" -c advice.detachedHead=false checkout --quiet "$TAG"
OPTS=(-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DLLAMA_CURL=OFF)
if [ "$(uname)" = Linux ] && command -v nvcc >/dev/null; then OPTS+=(-DGGML_CUDA=ON); fi
B=$SRC/build-$TAG
cmake -S "$SRC" -B "$B" "${OPTS[@]}"
cmake --build "$B" --config Release -j "$(getconf _NPROCESSORS_ONLN)" --target llama-server llama-cli
mkdir -p "$WS/bin/llama-$TAG"
cp "$B/bin/llama-server" "$B/bin/llama-cli" "$WS/bin/llama-$TAG/"
echo "Установлено: $WS/bin/llama-$TAG"
if [ $USE = 1 ]; then
  ln -sfn "llama-$TAG" "$WS/bin/current"
  echo "bin/current -> llama-$TAG: serve-mac.sh теперь запускает эту сборку."
  echo "ВНИМАНИЕ: старые слоты и прогретые сессии могут не подняться на новой сборке — пересобери их."
else
  echo "bin/current не тронут. Переключиться: $0 $TAG --use"
fi
