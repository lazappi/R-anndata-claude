# read_excel()

Status: ready-for-agent
Type: task
Blocked by: 01

## What

`read_excel()` through readxl (in `Suggests`, checked with `rlang::check_installed()`).

## Acceptance criteria

- Every xlsx row of the table passes
- Tests skip cleanly without readxl
- The full check (`scripts/check.sh --package` and `--tests`) passes
