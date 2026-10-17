# Backed operations table

Status: ready-for-agent
Type: task
Blocked by: none

## What

Write `tests/python/backed_cases.py` and generate the expected behaviour table (spec "Expected behaviour table"), registered in `scripts/regenerate-fixtures.sh` with a freshness test.
Use `python-oracle` to find every operation that errors, warns or changes the file in Python 0.13.4.

## Acceptance criteria

- The table covers every operation listed in the spec, and its freshness test passes
- `scripts/check.sh` passes

## Comments
