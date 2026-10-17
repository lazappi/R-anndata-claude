# Backed mode documentation

Status: done
Type: task
Blocked by: 05, 06

## What

A vignette section on backed mode, help pages for the new methods and `sparse_dataset()`, and NEWS.

## Acceptance criteria

- The vignette builds
- `scripts/check.sh` passes

## Comments

2026-10-18: Added a "Backed mode" vignette section (read with `backed`, `chunked_X()`/`chunk_X()`, `to_memory()`, `sparse_dataset()`).
Help pages (`sparse_dataset`, chunks, partial reads, `AnnData` backed section) and NEWS entries already existed from tickets 04 to 06.
A backed X cannot be indexed by name (`A backed array has no names`), so the vignette uses positions.
Full check and review pass.
