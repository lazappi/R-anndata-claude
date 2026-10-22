# Concatenation documentation

Status: done
Type: task
Blocked by: 06

## What

A vignette section on `concat()`, its help page and NEWS.

## Acceptance criteria

- The vignette builds
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-22: Added a "Concatenate" section to the vignette (joins, `fill_value`, named list keys, `label`, `index_unique`, merge strategies, Views, backed and lazy inputs).
The help page and NEWS entry already existed from earlier tickets, so NEWS only lost "(first part)".
`scripts/check.sh --package` and `--tests` pass and the reviewer passed.
