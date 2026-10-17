# Views: methods and writing

Status: in-progress
Type: task
Blocked by: 03 (and zarr-io/08 for writing zarr)

## What

Every public method on a View follows the operations table (`transpose()` raises Python's error), and writing a View to h5ad and zarr writes the subset, Structurally equivalent to Python writing the same View.

## Acceptance criteria

- The method and I/O rows of the operations table pass
- `scripts/check.sh` passes

## Decisions (human, 2026-10-17)

- The operations table rows for methods R does not have yet are not tested here.
  List them in the test file as deferred, each naming the sub-project that owns it: `to_memory`, `chunked_X` and `chunk_X` (`backed`), `write_csvs` and `write_loom` (`other-formats`).
  Those sub-projects must pass the rows when they add the methods.
- `write` is Python's shortcut for `write_h5ad` (`anndata.py:1744`): it is a separate Discovered item, and its row is tested once it exists.

## Comments

2026-10-17: Part done, ticket stays `in-progress`.
- `transpose()` and `t()` of a View (also of a View of a View) raise `anndata_view_transpose_error` (Python's `ValueError`), and the View stays a View
- Tests: transpose rows and writing a View to h5ad and zarr (values compared with the table's `write_h5ad`/`write_zarr` rows) in `test-views.R`

2026-10-17 (later run): Structural equivalence done.
- `tests/python/rewrite_view.py` writes `adata[obs, var]` with Python's defaults, and a test in `test-views.R` compares R's written View with it for h5ad and zarr (`expect_all_equivalent()` and `expect_python_equal()`)
- Only an obs and var subset is covered (no View of a View or Raw case)
- Remaining, see `fix_plan.md`: the table rows for `to_memory`, `write` alias, `write_csvs`, `write_loom`, `chunked_X`, `chunk_X`, which have no R method yet (they belong to other-formats/backed, so a human should say whether to skip them or stub nothing)
