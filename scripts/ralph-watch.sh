#!/usr/bin/env bash
# Follow the Ralph loop's progress from another terminal.
#
# Usage: scripts/ralph-watch.sh [log]
#
# With no argument, follows the most recent log in .ralph/logs/ and switches to
# each new log as the loop starts the next run (or resumes one after a usage limit).
# With a log, follows only that log.
# Press Ctrl-C to stop watching (the loop itself is not affected).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FORMAT="$ROOT/scripts/ralph-format.py"

if [ -n "${1:-}" ]; then
    echo "Watching $1"
    tail -n +1 -f "$1" | python3 "$FORMAT"
    exit
fi

latest_log() {
    /bin/ls -t "$ROOT"/.ralph/logs/*.jsonl 2>/dev/null | head -n 1 || true
}

current=""
tail_pid=""
stop_tail() {
    if [ -n "$tail_pid" ]; then
        kill "$tail_pid" 2>/dev/null || true
    fi
}
trap stop_tail EXIT
trap 'exit 130' INT TERM

while true; do
    latest="$(latest_log)"
    if [ -n "$latest" ] && [ "$latest" != "$current" ]; then
        # Killing tail closes the pipe, so the formatter exits too
        stop_tail
        current="$latest"
        echo "=== Watching $current"
        tail -n +1 -f "$current" > >(python3 "$FORMAT") &
        tail_pid=$!
    elif [ -z "$latest" ] && [ -z "$current" ]; then
        echo "Waiting for a Ralph log in $ROOT/.ralph/logs"
        current="none"
    fi
    sleep 5
done
