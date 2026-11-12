#!/usr/bin/env bash
# Act 5: what runs on the rented GPU, and the first lines of the bare-machine setup script.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/node.env"
exec ssh -i "$HOME/.ssh/id_ed25519_workshop" -o IdentitiesOnly=yes -p "$NODE_PORT" root@"$NODE_HOST" \
  'nvidia-smi --query-gpu=name,memory.used,utilization.gpu --format=csv; echo; head -20 /root/node-setup.sh'
