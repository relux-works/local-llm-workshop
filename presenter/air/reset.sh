#!/usr/bin/env bash
# After a rehearsal: close the four-Pi tmux session and move the generated pages to old/. Nothing is deleted.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); cd "$HERE"
if tmux has-session -t cloud 2>/dev/null; then tmux kill-session -t cloud; echo "tmux-сессия cloud закрыта."; fi
if [ -n "$(ls -A sites 2>/dev/null)" ]; then
  mkdir -p old; D=old/sites-$(date -u +%Y%m%dT%H%M%SZ); mv sites "$D"; mkdir sites
  echo "Страницы перенесены в $D, sites/ пустая."
else
  mkdir -p sites; echo "sites/ уже пустая."
fi
echo "Готово: ./0-check.sh"
