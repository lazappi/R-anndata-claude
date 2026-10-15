#!/usr/bin/env python3
"""Format Claude Code stream-json output from a Ralph run as readable progress lines.

Reads JSON lines on stdin and prints one line per notable event:
main-agent text and tool calls, subagent starts and finishes, subagent tool
calls (indented), errors, permission denials and the final result.
"""

import json
import sys
from datetime import datetime

WIDTH = 160

tools = {}  # tool_use_id -> short description, for matching denials and errors
agents = {}  # parent tool_use_id -> subagent type


def now():
    return datetime.now().strftime("%H:%M:%S")


def clip(text, width=WIDTH):
    text = " ".join(str(text).split())
    return text if len(text) <= width else text[: width - 1] + "…"


def emit(prefix, text, indent=False):
    pad = "    │ " if indent else ""
    print(f"{now()} {pad}{prefix} {clip(text)}", flush=True)


def describe_tool(name, args):
    if name == "Bash":
        return f"$ {args.get('command', '')}"
    if name in ("Read", "Edit", "Write"):
        return f"{name} {args.get('file_path', '')}"
    if name in ("Grep", "Glob"):
        return f"{name} {args.get('pattern', '')} {args.get('path', '')}".strip()
    if name in ("Agent", "Task"):
        return f"{args.get('subagent_type', 'agent')}: {args.get('description', '')}"
    return f"{name} {json.dumps(args)[:100]}"


def handle(event):
    kind = event.get("type")
    subtype = event.get("subtype")
    parent = event.get("parent_tool_use_id")
    sub = bool(parent)

    if kind == "assistant":
        for block in event.get("message", {}).get("content", []):
            if block.get("type") == "text" and block.get("text", "").strip():
                emit("💬", block["text"], sub)
            elif block.get("type") == "tool_use":
                desc = describe_tool(block.get("name"), block.get("input", {}))
                tools[block.get("id")] = desc
                if block.get("name") in ("Agent", "Task"):
                    agents[block.get("id")] = block.get("input", {}).get("subagent_type", "agent")
                    emit("🤖", desc, sub)
                else:
                    emit("→", desc, sub)
    elif kind == "user":
        content = event.get("message", {}).get("content", [])
        if isinstance(content, list):
            for block in content:
                if block.get("type") == "tool_result" and block.get("is_error"):
                    result = block.get("content")
                    if isinstance(result, list):
                        result = " ".join(c.get("text", "") for c in result if isinstance(c, dict))
                    emit("✗", f"{tools.get(block.get('tool_use_id'), 'tool')}: {result}", sub)
    elif kind == "system":
        if subtype == "init" and not sub:
            emit("▶", f"session {event.get('session_id', '')} model {event.get('model', '')}")
        elif subtype == "task_started" and event.get("subagent_type"):
            emit("▶", f"subagent {event.get('subagent_type')}: {event.get('description', '')}")
        elif subtype == "task_updated":
            status = event.get("patch", {}).get("status")
            if status in ("completed", "failed", "killed"):
                emit("✔" if status == "completed" else "✗", f"subagent task {status}")
        elif subtype == "permission_denied":
            emit("⛔", f"denied {tools.get(event.get('tool_use_id'), event.get('tool_name', ''))}")
    elif kind == "result":
        cost = event.get("total_cost_usd")
        cost = f" ${cost:.2f}" if cost is not None else ""
        emit("■", f"result {event.get('subtype')} ({event.get('num_turns')} turns{cost})")


def main():
    for line in sys.stdin:
        try:
            event = json.loads(line)
        except ValueError:
            if line.strip():
                emit("!", line.strip())
            continue
        try:
            handle(event)
        except Exception as err:  # never let formatting kill the pipeline
            emit("!", f"format error: {err}")


if __name__ == "__main__":
    try:
        main()
    except (KeyboardInterrupt, BrokenPipeError):
        # Quietly stop when interrupted or when the reader goes away (e.g. `| head`)
        sys.stderr.close()
