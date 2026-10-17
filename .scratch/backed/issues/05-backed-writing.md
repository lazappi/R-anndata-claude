# Writing backed objects

Status: ready-for-agent
Type: task
Blocked by: 03, 04

## What

Assigning X in `"r+"` mode, `write()`/`write_h5ad()` on a backed object, `copy(filename)`, `to_memory()`, setting `filename` (into, between and out of backed mode) and `min_rows_for_chunked_h5_copy`.

## Acceptance criteria

- The writing rows of the operations table pass, and the written files are Structurally equivalent to Python's
- `scripts/check.sh` passes

## Comments
