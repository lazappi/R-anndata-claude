# Raw class and raw slot

Status: needs-triage
Type: task
Blocked by: 05, 07

## What

The `Raw` R6 class (`src/anndata/_core/raw.py`) and the `raw` Slot (`anndata.py:723-735`).

- Holds `X`, `var` and `varm`, sharing observations with the parent
- Fields `X`, `var`, `varm`, `var_names`, `obs_names`, `n_obs`, `n_vars`, `shape`
- `raw[i, j]` subsetting, `raw$to_adata()` and `raw$copy()`
- `adata$raw <- other` requires an `AnnData` and stores its X, var and varm, and `NULL` removes it
- The `raw` constructor argument accepts an `AnnData` or a named list with `X`, `var` and `varm`

## Acceptance criteria

- Each item above is tested, including errors by class
- `scripts/check.sh` passes

## Comments
