# Views documentation

Status: done
Type: task
Blocked by: 04

## What

Document Views: a vignette paragraph, the `AnnData()` help page (lazy and snapshot parts, copy-on-write, the documented deviation for extracted values) and NEWS.

## Acceptance criteria

- The vignette builds and the help pages describe the deviation
- `scripts/check.sh` passes

## Comments

2026-10-17: Extended the `Views` section of the `AnnData()` help page (copy-on-write forms, warning, `copy()`, `transpose()`, writing, and the documented deviation for extracted values), added a vignette View example and a NEWS line.
Full check passes (0 errors, warnings, notes) and the reviewer passed.
