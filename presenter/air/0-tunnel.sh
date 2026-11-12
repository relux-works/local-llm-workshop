#!/usr/bin/env bash
# Prep, its own tab, keep it open all workshop: localhost:8081 on this laptop -> llama-server on the GPU node.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/node.env"; export NODE_HOST NODE_PORT
echo "Туннель к узлу $NODE_HOST:$NODE_PORT -> localhost:8081. Вкладку не закрывать."
exec "$HERE/cloud/scripts/air-cloud.sh" tunnel
