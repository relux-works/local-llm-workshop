#!/usr/bin/env bash
# Act 1, window 0: start Qwen3.8-27B. The server log stays in this window.
set -eu
WS=${WS:-$HOME/workshop}; cd "$WS"
exec "$WS/serve-mac.sh" q27b
