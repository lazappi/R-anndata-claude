# chunked_X, chunk_X and read_elem_partial

Status: done
Type: task
Blocked by: 03, 04

## What

`chunked_X()` and `chunk_X()` (for backed and in-memory objects), `read_elem_partial()`, and the deferred Views table rows for `to_memory`, `chunked_X` and `chunk_X`.

## Acceptance criteria

- Their rows of the backed and Views operations tables pass
- `scripts/check.sh` passes

## Comments

2026-10-18: Done.
- `chunked_X(chunk_size)` returns a list of `list(chunk, start, end)` (1-based inclusive rows, an R deviation from Python's generator and 0-based half-open ranges), `chunk_X(select, replace)` takes a length-1 number as a random count and anything else as an R row index (`I()` for a single row), result always dense (`R/chunks.R`)
- `read_elem_partial(store, path, items, rows, cols)` is internal like `read_elem()` (`R/backed-partial.R`), R indices, no dropping to vectors, dense/data frame/categorical need increasing positions, sparse accepts any order, arrays above 2-D raise `anndata_partial_read_error`
- Views rows `chunked_X` and `chunk_X` are tested in `test-views.R`, the `to_memory` row was already done by backed/05
- `chunk_X(<count>)` is random in Python, so tests compare sizes and membership only
