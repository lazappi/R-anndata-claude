# Writing backed objects

Status: in-progress
Type: task
Blocked by: 03, 04

## What

Assigning X in `"r+"` mode, `write()`/`write_h5ad()` on a backed object, `copy(filename)`, `to_memory()`, setting `filename` (into, between and out of backed mode) and `min_rows_for_chunked_h5_copy`.

## Acceptance criteria

- The writing rows of the operations table pass, and the written files are Structurally equivalent to Python's
- `scripts/check.sh` passes

## Comments

2026-10-17, part 1 (status stays `in-progress`):

- Done: `write()`/`write_h5ad()` of a backed object (new file, in place, `as_dense`, compression), the methods re-point the object at the new file (closed), the function does not (Python's split), `copy(filename)`, `to_memory()`, Views of backed objects writing and `to_memory()`. Tests are in `test-backed-writing.R`.
- A View has its own empty file manager in R (`isbacked` is `FALSE`, Python says `TRUE`), so `write_h5ad()` looks through `view_info()$parent`.
- Deviations from Python, to be confirmed by the human:
  - `copy_twice`: Python overwrites the first copy's open file in `"r+"` mode, rhdf5 cannot truncate an open file, so R errors in both modes
  - `view_write_same`: Python writes a corrupt in-place update and fails, R refuses with `anndata_invalid_argument_error`
  - A write to a new file that exists truncates it, Python opens it in mode `"a"` and updates it
  - A backed `raw` written in place is `anndata_not_supported_error` (Python fails with `AttributeError`), written to a new file it works in R (Python fails)
  - X is read whole into memory when copying to a new file (no `min_rows_for_chunked_h5_copy` chunking yet)
- Remaining (queue sub-items): X assignment in `"r+"` mode (rows `X_assign_*`, `X_item`, `X_del`, `layers_none_assign`, `write_after_X_assign`), the `filename` setter (rows `filename_*`), chunked copy with `min_rows_for_chunked_h5_copy`, raw rows (`raw_X_assign`, `raw_assign`, `raw_operations`), `write_obs_edit`, `view_*_assign` rows.

2026-10-17, part 2 (status stays `in-progress`):

- Done: X assignment and the `view_*_assign` rows, tests in `test-backed-assign.R`.
- `isbacked` is now "has a filename and X is not in memory" (Python's `Layers.isbacked`), so assigning X (or `layers[[NA]]`) keeps the file but ends backed mode, and `write()` then asks for a filename. `X <- NULL` on a backed object is a no-op, and on an assigned X it restores the placeholder from the file.
- `adata$X[i, j] <- v` writes into the file for dense X in `"r+"` (`[<-.backed_dense`, any R index form, read-modify-write of the touched block), `anndata_read_only_error` in `"r"`, `anndata_not_supported_error` for sparse.
- A View of a backed object now warns then raises the "pass a filename" error on any change except replacing X (Python's `_copy` of a backed object), and the View stays a View.
- Deviation: `view$X[1, 1] <- 5` makes the View actual with a warning, Python silently changes nothing (documented in the `AnnData()` help).
2026-10-18, part 3 (status stays `in-progress`):

- Done: the `filename` setter (`private$set_filename()`, `file_manager$to_memory_mode()`), tests in `test-backed-filename.R`: `NULL` (reads X into memory), same path (no-op), new path in memory (writes with X dense, opens `"r+"`), new path when backed (updates the file, renames, reopens `"r+"`), failed move, X assigned first, View of a backed object.
- Deviations: the View of a backed object fails before moving anything (Python renames the file first and leaves it corrupt), a failed move raises `anndata_file_not_found_error`.
- Not done: a backed `raw` X is not converted to memory by `filename <- NULL` (belongs with the raw rows, row `filename_none` has `raw_X`).
- The full `scripts/check.sh` and the reviewer pass. `filename` is no longer read-only, so it left the read-only loop in `test-anndata-class.R`.

Part 2 note: the full `scripts/check.sh` passed. The reviewer asked for bool/integer item assignment tests and a View-of-assigned-X test (added) and a Python structural comparison of the `X_item` file (not done, the in-place write only changes values, so the next run may add `expect_all_equivalent`).
