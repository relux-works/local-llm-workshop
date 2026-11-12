#!/usr/bin/env bash
# The cloud act on the presenter's laptop: an SSH tunnel to the GPU node, four Pi sessions that build landing pages in
# parallel, and a local web server for the results.
#   air-cloud.sh tunnel   keep this running in its own tab: localhost:8081 -> llama-server on the node
#   air-cloud.sh grid     tmux 2x2, one Pi per pane, each with its own prompt and folder
#   air-cloud.sh pane N   one Pi for landing N (1-4) in the current terminal: four Ghostty splits instead of tmux
#   air-cloud.sh web      http://localhost:8000 serves the four folders
# Set NODE_HOST and NODE_PORT to the node's direct SSH address (Vast shows it under "IP & port info").
set -eu
CW=${CW:-$HOME/workshop-cloud}
KEY=${KEY:-$HOME/.ssh/id_ed25519_workshop}
HERE=$(cd "$(dirname "$0")/.." && pwd)
SITES=(1-efemera 2-tihiy-chas 3-oblakoprokat 4-kvant-himchistka)
mkdir -p "$CW/sites"
case "${1:-}" in
  tunnel)
    : "${NODE_HOST:?set NODE_HOST}" "${NODE_PORT:?set NODE_PORT}"
    exec ssh -i "$KEY" -o IdentitiesOnly=yes -o ServerAliveInterval=30 -o ExitOnForwardFailure=yes \
      -N -L 8081:127.0.0.1:8080 -p "$NODE_PORT" root@"$NODE_HOST" ;;
  grid)
    curl -sf http://127.0.0.1:8081/health >/dev/null || { echo "no tunnel: run '$0 tunnel' first"; exit 1; }
    tmux kill-session -t cloud 2>/dev/null || true
    for s in "${SITES[@]}"; do mkdir -p "$CW/sites/$s"; done
    run() { echo "cd '$CW/sites/$1' && pi --provider ws-vast --model flashnext \"\$(cat '$HERE/prompts/$1.md')\""; }
    tmux new-session -d -s cloud -x 240 -y 60 "$(run "${SITES[0]}"); exec \$SHELL"
    tmux split-window -h -t cloud "$(run "${SITES[1]}"); exec \$SHELL"
    tmux split-window -v -t cloud:0.0 "$(run "${SITES[2]}"); exec \$SHELL"
    tmux split-window -v -t cloud:0.2 "$(run "${SITES[3]}"); exec \$SHELL"
    tmux select-layout -t cloud tiled
    exec tmux attach -t cloud ;;
  pane)
    i=${2:?usage: $0 pane 1-4}; s=${SITES[$((i-1))]}
    curl -sf http://127.0.0.1:8081/health >/dev/null || { echo "no tunnel: run '$0 tunnel' first"; exit 1; }
    mkdir -p "$CW/sites/$s" && cd "$CW/sites/$s"
    exec pi --provider ws-vast --model flashnext "$(cat "$HERE/prompts/$s.md")" ;;
  web)
    cd "$CW/sites" && echo "open http://localhost:8000/" && exec python3 -m http.server 8000 ;;
  *) echo "usage: $0 tunnel|grid|pane N|web"; exit 2 ;;
esac
