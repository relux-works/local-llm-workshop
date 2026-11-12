#!/usr/bin/env bash
# Act 4, window 1: restore the prewarmed 200k slot of Qwen3.8-Flash-Next and open Pi on that session.
exec "$(dirname "$0")/_pi-200k.sh" flashnext Flash-Next
