# Views: copy-on-write

Status: ready-for-agent
Type: task
Blocked by: 02

## What

Copy-on-write for every assignment and deletion through a View, including nested forms, with Python's warnings (spec "Behaviour").
The parent is never changed.

## Acceptance criteria

- The modification rows of the operations table pass for every Slot
- `scripts/check.sh` passes

## Comments
