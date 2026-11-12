#!/usr/bin/env bash
# Act 5: the "workhorse" — Pi on the cloud model with the workshop context. Usage: 5-workhorse.sh ["вопрос"]
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); cd "$HERE"
Q=${1:-"Коротко: какие цифры мы сегодня показали?"}
curl -sf -m 5 http://127.0.0.1:8081/health >/dev/null || { echo "Туннель не отвечает — ./0-tunnel.sh в отдельной вкладке."; exit 3; }
exec pi --provider ws-vast --model flashnext @cloud/workhorse.md "$Q"
