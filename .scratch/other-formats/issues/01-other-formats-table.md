# Other formats table

Status: ready-for-agent
Type: task
Blocked by: none

## What

Write `tests/python/other_formats_cases.py` and generate the input files and expected behaviour table (spec "Expected behaviour table"), with a hash-based freshness test.
Add openpyxl to the uv project in `tests/python`.

## Acceptance criteria

- The table covers every input and `write_csvs` case listed in the spec
- The full check (`scripts/check.sh --package` and `--tests`) passes
