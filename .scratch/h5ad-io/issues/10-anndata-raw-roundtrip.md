# AnnData and Raw, read_h5ad and write_h5ad basics

Status: done
Type: task
Blocked by: 07, 08, 09, core-object/09

## What

Register `anndata` 0.1.0 and `raw` 0.1.0 and add `read_h5ad(filename)` and `write_h5ad(adata, filename)`, plus `adata$write_h5ad(filename)` and `adata$unwriteable(store_type = NULL)` (`anndata.py:1492-1577`).

- Root encoding attributes, always-written empty dict groups for obsm, varm, obsp, varp, layers and uns
- The `NA` layer (ADR 0004) written to `/X`, never inside `/layers`
- File with no `X` reads as `NULL`
- Raw with its own var and varm
- Empty and degenerate shapes: 0 observations, 0 variables, no X, empty Slots
- `backed` errors with "not yet supported"
- Fixtures for raw, degenerate shapes and empty Slots

## Acceptance criteria

- All three round-trip directions pass for each fixture
- `unwriteable()` is tested against Python
- `scripts/check.sh` passes

## Comments

2026-10-16: Done.
Registered `anndata` and `raw` (`R/io-values-anndata.R`), added `read_h5ad()`, `write_h5ad()`, `adata$write_h5ad(filename, ...)` and `adata$unwriteable(store_type)` (`R/io-h5ad.R`).
- `write_h5ad()` has only `convert_strings_to_categoricals` so far, ticket 11 adds `compression`, `compression_opts`, `as_dense`, `as_sparse` and friends. `read_h5ad()` has only `backed`.
- Higher-than-2-D X and layers are refused by the constructor, so the reader sets them after construction, which only warns (`anndata_non_2d_warning`). Writing them raises `anndata_non_2d_error`.
- New fixtures `anndata_raw_own_var`, `anndata_raw_0_obs`, `anndata_raw_0_vars` and `unwriteable_cases.json` (from `tests/python/unwriteable_cases.py`, guarded by a freshness test).
- `compare.py` now takes several pairs and `rewrite_h5ad.py` rewrites whole h5ad files, each in one Python process.
- `unwriteable()` also reports lists that cannot be written (unnamed or duplicated names), which Python has no equivalent for.
