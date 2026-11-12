#!/usr/bin/env bash
# Act 2, window 1: restore the prewarmed 200k slot of Qwen3.8-27B and open Pi on that session.
exec "$(dirname "$0")/_pi-200k.sh" qwen27b Qwen3.8-27B
