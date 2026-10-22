# legacy-formats: raw.X, raw.var and the neighbors move

Status: ready-for-agent
Type: task
Blocked by: 04

## What

- `raw.X`, `raw.var` (and `raw.varm` if ticket 02 finds 0.6.22 writes it) as root members (`_read_legacy_raw`, `h5ad.py:299`), with their `OldFormatWarning`s, h5ad only (the zarr path has no readable release)
- Old `uns["neighbors"]` `connectivities` and `distances` moved to `obsp` (`_move_adj_mtx`, `anndata.py:492`) with Python's `FutureWarning`, in the file's order, for 0.6.22, 0.7.8 and 0.10.9 (h5ad and zarr)

## Acceptance criteria

- The fixtures of ticket 02 read to the values and warnings in the expectation table
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments
