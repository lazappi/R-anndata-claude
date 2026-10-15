#!/usr/bin/env python3
"""Inspect a Ralph run log (Claude Code stream-json).

Usage:
  ralph-log.py summary <log>   print the final result and cost
  ralph-log.py denials <log>   list permission denials
  ralph-log.py limit <log>     if the run ended on a usage limit, print
                               "<reset epoch seconds or 0> <session id>" and exit 0,
                               otherwise exit 1
"""

import json
import sys


def events(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            try:
                yield json.loads(line)
            except ValueError:
                continue


def last_result(path):
    result = None
    for event in events(path):
        if event.get("type") == "result":
            result = event
    return result


def summary(path):
    result = last_result(path)
    if not result:
        print("--- no result event found, see log")
        return
    cost = result.get("total_cost_usd")
    print(
        f"--- result ({result.get('subtype')}, {result.get('num_turns')} turns"
        + (f", ${cost:.2f}" if cost is not None else "")
        + ")"
    )
    print((result.get("result") or "").strip()[-2000:])


def denials(path):
    tools, denied = {}, []
    for event in events(path):
        if event.get("type") == "assistant":
            for block in event.get("message", {}).get("content", []):
                if block.get("type") == "tool_use":
                    args = block.get("input", {})
                    tools[block.get("id")] = (
                        args.get("command") or args.get("file_path") or block.get("name")
                    )
        elif event.get("type") == "system" and event.get("subtype") == "permission_denied":
            denied.append(tools.get(event.get("tool_use_id"), event.get("tool_name", "?")))
    if denied:
        print(f"--- {len(denied)} permission denial(s):")
        for item in denied:
            print(f"    {item}")


def limit(path):
    reset, session, result = 0, None, None
    for event in events(path):
        if event.get("session_id"):
            session = event["session_id"]
        info = event.get("rate_limit_info") or {}
        if info.get("status") == "rejected" and info.get("resetsAt"):
            reset = int(info["resetsAt"])
        if event.get("type") == "result":
            result = event
    if not result or not session:
        return 1
    hit = (
        result.get("api_error") == "usage_limit_reached"
        or result.get("api_error_status") == 429
        or "limit" in str(result.get("result", "")).lower() and result.get("is_error")
    )
    if not hit:
        return 1
    print(f"{reset} {session}")
    return 0


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("summary", "denials", "limit"):
        print(__doc__, file=sys.stderr)
        return 2
    command, path = sys.argv[1], sys.argv[2]
    if command == "summary":
        summary(path)
    elif command == "denials":
        denials(path)
    else:
        return limit(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
