#!/usr/bin/env bash
# Act 5, its own tab: tmux 2x2, four Pi sessions build four landing pages in parallel on the cloud model.
exec "$(cd "$(dirname "$0")" && pwd)/cloud/scripts/air-cloud.sh" grid
