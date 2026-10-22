# Lazy reading documentation

Status: done
Type: task
Blocked by: 07

## What

A vignette section on lazy reading, help pages and NEWS.

## Acceptance criteria

- The vignette builds
- `scripts/check.sh` passes

## Comments

2026-10-22: Added a "Lazy reading" vignette section (`read_lazy()`, `to_memory()`, `read_elem_lazy(chunks =)`) and a NEWS bullet. Help pages for `read_lazy()` and `read_elem_lazy()` already existed with examples. Package check and the full test suite pass.
