#!/usr/bin/env bash
# Follow a Ralph run's progress from another terminal.
#
# Usage: scripts/ralph-watch.sh [log]
#
# With no argument, follows the most recent log in .ralph/logs/.
# Press Ctrl-C to stop watching (the run itself is not affected).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${1:-$(/bin/ls -t "$ROOT"/.ralph/logs/*.jsonl 2>/dev/null | head -n 1)}"

if [ -z "$LOG" ] || [ ! -f "$LOG" ]; then
    echo "No Ralph log found in $ROOT/.ralph/logs" >&2
    exit 1
fi

echo "Watching $LOG"
tail -n +1 -f "$LOG" | python3 "$ROOT/scripts/ralph-format.py"
