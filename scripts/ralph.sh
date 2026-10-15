#!/usr/bin/env bash
# Run the Ralph loop: one fresh Claude Code run per item in fix_plan.md.
#
# Usage: scripts/ralph.sh [max_runs]
#
# Stops when:
#   - a STOP file exists at the repository root (create it to stop after the current run)
#   - a run writes .ralph/halt (no unblocked items left)
#   - max_runs (default 20, or RALPH_MAX_RUNS) runs have completed
#   - RALPH_MAX_IDLE (default 3) runs in a row produce no commit
#   - the working tree is dirty before a run starts
#
# Each run is logged to .ralph/logs/<timestamp>-<run>.jsonl (stream-json) and shown
# live as readable progress (scripts/ralph-format.py). Follow a run from another
# terminal with scripts/ralph-watch.sh.
# Runs use ralph/settings.json on top of the project settings: Sonnet as the main
# model, plugins disabled, only project subagents, and no edits to specs, ADRs or
# loop configuration. Anything not allowlisted is denied (dontAsk mode).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

MAX_RUNS="${1:-${RALPH_MAX_RUNS:-20}}"
MAX_IDLE="${RALPH_MAX_IDLE:-3}"
LOG_DIR=".ralph/logs"
mkdir -p "$LOG_DIR" .ralph/oracle
rm -f .ralph/halt

idle=0
for ((run = 1; run <= MAX_RUNS; run++)); do
    if [ -f STOP ]; then
        echo "STOP file found, stopping before run $run"
        break
    fi
    if [ -n "$(git status --porcelain)" ]; then
        echo "Working tree is dirty, stopping before run $run. Inspect and commit or discard first."
        git status --short
        exit 1
    fi

    log="$LOG_DIR/$(date +%Y%m%d-%H%M%S)-$run.jsonl"
    before="$(git rev-parse HEAD)"
    echo "=== Run $run/$MAX_RUNS ($(date '+%F %T')) log: $log"

    claude -p \
        --model sonnet \
        --settings ralph/settings.json \
        --permission-mode dontAsk \
        --disable-slash-commands \
        --output-format stream-json \
        --verbose \
        <PROMPT.md 2>&1 | tee "$log" | python3 scripts/ralph-format.py
    status=${PIPESTATUS[0]}

    # Print the run's final summary
    python3 - "$log" <<'EOF'
import json, sys
result = None
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    try:
        event = json.loads(line)
    except ValueError:
        continue
    if event.get("type") == "result":
        result = event
if result:
    cost = result.get("total_cost_usd")
    print(f"--- result ({result.get('subtype')}, {result.get('num_turns')} turns"
          + (f", ${cost:.2f}" if cost is not None else "") + ")")
    print((result.get("result") or "").strip()[-2000:])
else:
    print("--- no result event found, see log")
EOF

    # List permission denials so allowlist gaps are visible
    python3 - "$log" <<'EOF'
import json, sys
tools, denied = {}, []
for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
    try:
        event = json.loads(line)
    except ValueError:
        continue
    if event.get("type") == "assistant":
        for block in event.get("message", {}).get("content", []):
            if block.get("type") == "tool_use":
                args = block.get("input", {})
                tools[block.get("id")] = args.get("command") or args.get("file_path") or block.get("name")
    elif event.get("type") == "system" and event.get("subtype") == "permission_denied":
        denied.append(tools.get(event.get("tool_use_id"), event.get("tool_name", "?")))
if denied:
    print(f"--- {len(denied)} permission denial(s):")
    for d in denied:
        print(f"    {d}")
EOF

    after="$(git rev-parse HEAD)"
    if [ "$before" = "$after" ]; then
        idle=$((idle + 1))
        echo "No commit this run ($idle/$MAX_IDLE idle, exit status $status)"
    else
        idle=0
        git log --oneline "$before..$after"
    fi

    if [ -n "$(git status --porcelain)" ]; then
        echo "Run $run left uncommitted changes, stopping. Inspect the log and the changes, then commit or discard."
        git status --short
        exit 1
    fi

    if [ -f .ralph/halt ]; then
        echo "Loop halted: $(cat .ralph/halt)"
        break
    fi
    if [ "$idle" -ge "$MAX_IDLE" ]; then
        echo "Stopping after $idle runs in a row without a commit"
        break
    fi
done
