#!/usr/bin/env bash
# Act 5, its own tab: serve the landing pages at http://localhost:8000/
exec "$(cd "$(dirname "$0")" && pwd)/cloud/scripts/air-cloud.sh" web
