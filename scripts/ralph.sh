#!/usr/bin/env bash
# Run the Ralph loop: one fresh Claude Code run per item in fix_plan.md.
#
# Usage: scripts/ralph.sh [max_runs]
#
# Stops when:
#   - a STOP file exists at the repository root (create it to stop after the current run)
#   - a run writes .ralph/halt (no unblocked items left, or a human checkpoint)
#   - max_runs (default 20, or RALPH_MAX_RUNS) runs have completed
#   - RALPH_MAX_IDLE (default 3) runs in a row produce no commit
#   - the working tree is dirty before a run starts, unless the last run was
#     interrupted by a usage limit (then that session is resumed)
#   - a usage limit resets more than RALPH_MAX_LIMIT_WAIT seconds away (default 6 hours)
#
# Usage limits: when a run ends because the plan's usage limit was reached, the
# script waits until the limit resets and resumes the same session (--resume), so
# the run keeps its context and finishes its item.
#
# Each run is logged to .ralph/logs/<timestamp>-<run>.jsonl (stream-json) and shown
# live as readable progress (scripts/ralph-format.py). Follow a run from another
# terminal with scripts/ralph-watch.sh.
# Runs use ralph/settings.json on top of the project settings: Sonnet as the main
# model, plugins disabled, only project subagents, and no edits to specs, ADRs or
# loop configuration. Anything not allowlisted is denied (dontAsk mode).
set -uo pipefail

# In print mode Claude Code kills background subagents still running 10 minutes after
# the last turn. Allow 30 minutes so a slow full check cannot cut a run short.
export CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS="${CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS:-1800000}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

MAX_RUNS="${1:-${RALPH_MAX_RUNS:-20}}"
MAX_IDLE="${RALPH_MAX_IDLE:-3}"
MAX_LIMIT_WAIT="${RALPH_MAX_LIMIT_WAIT:-21600}"
MAX_RESUMES="${RALPH_MAX_RESUMES:-3}"
LOG_DIR=".ralph/logs"
mkdir -p "$LOG_DIR" .ralph/oracle
rm -f .ralph/halt

RESUME_PROMPT="Your previous turn was interrupted because the usage limit was reached. The limit has now reset. Continue the same item from where you left off, following PROMPT.md: check the current state with git status and the ticket, finish the work, pass the checks and review, then do the bookkeeping and commit."

# Run Claude Code with the loop settings. Arguments: log file, then extra claude
# arguments. The prompt is read from stdin.
run_claude() {
    local log="$1"
    shift
    claude -p \
        --model sonnet \
        --settings ralph/settings.json \
        --permission-mode dontAsk \
        --disable-slash-commands \
        --output-format stream-json \
        --verbose \
        "$@" 2>&1 | tee "$log" | python3 scripts/ralph-format.py
    return "${PIPESTATUS[0]}"
}

# If the log ended on a usage limit, wait for the reset and resume that session,
# repeating if the resumed session hits the limit again. Returns non-zero if the
# loop should stop.
resume_after_limit() {
    local log="$1" info reset session now wait attempt=0
    while info="$(python3 scripts/ralph-log.py limit "$log")"; do
        attempt=$((attempt + 1))
        if [ "$attempt" -gt "$MAX_RESUMES" ]; then
            echo "Usage limit hit $MAX_RESUMES times in a row, stopping"
            return 1
        fi
        read -r reset session <<<"$info"
        now="$(date +%s)"
        if [ "$reset" -gt 0 ]; then
            wait=$((reset - now + 60))
        else
            wait=1800
        fi
        [ "$wait" -lt 60 ] && wait=60
        if [ "$wait" -gt "$MAX_LIMIT_WAIT" ]; then
            echo "Usage limit resets in $((wait / 60)) minutes, more than RALPH_MAX_LIMIT_WAIT allows, stopping"
            echo "Restart scripts/ralph.sh after the reset, and it resumes session $session"
            return 1
        fi
        echo "Usage limit reached, waiting $((wait / 60)) minutes until $(date -r $((now + wait)) '+%H:%M') to resume session $session"
        sleep "$wait"
        log="${log%.jsonl}-resume$attempt.jsonl"
        echo "=== Resuming session $session ($(date '+%F %T')) log: $log"
        run_claude "$log" --resume "$session" <<<"$RESUME_PROMPT"
        python3 scripts/ralph-log.py summary "$log"
        python3 scripts/ralph-log.py denials "$log"
    done
    return 0
}

# Recover from a previous invocation that stopped on a usage limit mid-run
if [ -n "$(git status --porcelain)" ]; then
    last="$(/bin/ls -t "$LOG_DIR"/*.jsonl 2>/dev/null | head -n 1)"
    if [ -n "$last" ] && python3 scripts/ralph-log.py limit "$last" >/dev/null; then
        echo "Working tree is dirty from a run interrupted by a usage limit, resuming it"
        resume_after_limit "$last" || exit 1
        if [ -n "$(git status --porcelain)" ]; then
            echo "The resumed run left uncommitted changes, stopping. Inspect and commit or discard."
            git status --short
            exit 1
        fi
    fi
fi

idle=0
for ((run = 1; run <= MAX_RUNS; run++)); do
    if [ -f STOP ]; then
        echo "STOP file found, stopping before run $run"
        break
    fi
    if [ -f .ralph/halt ]; then
        echo "Loop halted: $(cat .ralph/halt)"
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

    run_claude "$log" <PROMPT.md
    status=$?
    python3 scripts/ralph-log.py summary "$log"
    python3 scripts/ralph-log.py denials "$log"

    resume_after_limit "$log" || exit 1

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
