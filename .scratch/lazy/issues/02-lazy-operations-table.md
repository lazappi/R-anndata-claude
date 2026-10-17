# Lazy operations table

Status: ready-for-agent
Type: task
Blocked by: none

## What

Write `tests/python/lazy_cases.py` and generate the expected behaviour table (spec "Expected behaviour table"), registered in `scripts/regenerate-fixtures.sh` with a hash-based freshness test like the other tables.

## Acceptance criteria

- The table covers every operation listed in the spec
- `scripts/check.sh` passes

## Comments
