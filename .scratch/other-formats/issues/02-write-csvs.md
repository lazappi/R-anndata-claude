# write_csvs()

Status: done
Type: task
Blocked by: 01

## What

`write_csvs()` and `adata$write_csvs()` (spec "Scope"), including Views.
Mark the Views table's `write_loom` rows as out of scope (deprecated in Python, see the spec) instead of deferred.

## Acceptance criteria

- Every `write_csvs` row of the table and of the Views table passes
- Files written by R and Python are equal when pandas reads them back
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: Done.
- `write_csvs(adata, dirname, skip_data, sep)` and `adata$write_csvs()` in `R/io-csvs.R`. Every table case matches Python's file names and exact text, so pandas reads them the same (`test-io-csvs.R`). The Views row is tested in `test-views.R`, and the `write_loom` rows are marked out of scope there.
- Floats use a port of Python's `repr` (`format_float()`, float32 via `to_float32()`). Dict cells use `py_repr()`, including numpy's `repr` of 1-d arrays that fit on one line (`py_array_repr()`). Longer or multi-dimensional arrays in a dict raise `anndata_not_supported_error` because numpy wraps lines.
- Dicts holding complex numbers or unnamed lists raise `anndata_not_supported_error`.
- Not verified against Python: float32 values at exponents beyond 1e16, sparse values inside `obsm` (densified).
- `other_formats_table()` moved to `helper-other-formats.R`.
- `test-views.R:301,308` and `test-subsetting.R:98` testthat warnings (implicit modification) and the `rhdf5` `h5tid` warnings existed before this ticket.
