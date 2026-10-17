# chunked_X, chunk_X and read_elem_partial

Status: ready-for-agent
Type: task
Blocked by: 03, 04

## What

`chunked_X()` and `chunk_X()` (for backed and in-memory objects), `read_elem_partial()`, and the deferred Views table rows for `to_memory`, `chunked_X` and `chunk_X`.

## Acceptance criteria

- Their rows of the backed and Views operations tables pass
- `scripts/check.sh` passes

## Comments
