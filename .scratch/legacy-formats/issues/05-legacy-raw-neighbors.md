# legacy-formats: raw.X, raw.var and the neighbors move

Status: done
Type: task
Blocked by: 04

## What

- `raw.X`, `raw.var` (and `raw.varm` if ticket 02 finds 0.6.22 writes it) as root members (`_read_legacy_raw`, `h5ad.py:299`), with their `OldFormatWarning`s, h5ad only (the zarr path has no readable release)
- Old `uns["neighbors"]` `connectivities` and `distances` moved to `obsp` (`_move_adj_mtx`, `anndata.py:492`) with Python's `FutureWarning`, in the file's order, for 0.6.22, 0.7.8 and 0.10.9 (h5ad and zarr)

## Acceptance criteria

- The fixtures of ticket 02 read to the values and warnings in the expectation table
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: Done.

- `read_legacy_raw()` (`R/io-legacy.R`) reads `raw.X`, `raw.var` (compound dataset or dataframe) and `raw.varm` into the list `AnnData()` takes as `raw`, only when `raw.X` exists as in Python, and raises `anndata_io_registry_error` when a current `raw` coexists with any `raw.*` member
- `move_adjacency_matrices()` moves 2-D `distances` then `connectivities` from `uns$neighbors` to `obsp` with `warn_future()`, in `read_anndata_elem()` for every AnnData group (Python does it in the constructor)
- Tests in `test-io-legacy.R` compare raw, `obsp` and warnings to the table for 0.6.22, 0.7.8 (h5ad and zarr) and 0.10.9 (h5ad and zarr), the warning order is not checked because the table is sorted
- `read_legacy_elem()` now also collects `anndata_future_warning` messages as `$future`
