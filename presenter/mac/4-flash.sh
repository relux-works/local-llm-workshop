#!/usr/bin/env bash
# Act 4, window 0: start Qwen3.8-Flash-Next (stop Qwen first: Ctrl-C in this window). Loads from LaCie in ~2.5 min.
set -eu
WS=${WS:-$HOME/workshop}; cd "$WS"
exec "$WS/serve-mac.sh" flashnext
