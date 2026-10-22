# Concat table

Status: ready-for-agent
Type: task
Blocked by: none

## What

Write `tests/python/concat_cases.py` and generate the expected behaviour table (spec "Expected behaviour table"), with a hash-based freshness test.

## Acceptance criteria

- The table covers every combination listed in the spec
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments
