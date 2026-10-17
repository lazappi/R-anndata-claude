# Views: methods and writing

Status: in-progress
Type: task
Blocked by: 03 (and zarr-io/08 for writing zarr)

## What

Every public method on a View follows the operations table (`transpose()` raises Python's error), and writing a View to h5ad and zarr writes the subset, Structurally equivalent to Python writing the same View.

## Acceptance criteria

- The method and I/O rows of the operations table pass
- `scripts/check.sh` passes

## Comments

2026-10-17: Part done, ticket stays `in-progress`.
- `transpose()` and `t()` of a View (also of a View of a View) raise `anndata_view_transpose_error` (Python's `ValueError`), and the View stays a View
- Tests: transpose rows and writing a View to h5ad and zarr (values compared with the table's `write_h5ad`/`write_zarr` rows) in `test-views.R`
- Remaining, see `fix_plan.md`: Structural equivalence with Python writing the same View (`expect_python_equal()`), and the table rows for `to_memory`, `write` alias, `write_csvs`, `write_loom`, `chunked_X`, `chunk_X`, which have no R method yet (they belong to other-formats/backed, so a human should say whether to skip them or stub nothing)
