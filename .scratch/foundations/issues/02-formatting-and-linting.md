# Formatting and linting

Status: done
Type: task
Blocked by: 01

## What

Configure `air` and `lintr` as described in the "Tooling" section of `.scratch/foundations/spec.md`.

- `air.toml` at the root
- `.lintr` at the root, using the default linters, with any disabled linter justified in a comment
- Both config files added to `.Rbuildignore`
- Every existing R file formatted

## Acceptance criteria

- `air format --check .` reports no changes
- `lintr::lint_package()` returns no lints
- `devtools::check()` still passes cleanly

## Comments

2026-10-15: Added `air.toml` (80 columns, 2 spaces) and `.lintr` (default linters, none disabled). Both were already in `.Rbuildignore`. `air format` changed no files.
`air format --check .` and `lintr::lint_package()` are clean. `devtools::check()` gives 0 errors and 0 warnings, plus one environmental NOTE ("unable to verify current time" for future file timestamps, not caused by the repo). Ticket 03 could set `_R_CHECK_FUTURE_FILE_TIMESTAMPS_=false` in `scripts/check.sh` if it recurs.
Released as `0.0.0.9001`.
