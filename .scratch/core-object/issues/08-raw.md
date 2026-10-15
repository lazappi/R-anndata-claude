# Raw class and raw slot

Status: done
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

### 2026-10-15

Implemented `Raw` (`R/raw.R`), the `raw` Slot and constructor argument, and `R/index.R` (index normalisation and slot subsetting helpers).
- `normalize_index()` raises `anndata_index_error` for NA, zero, unknown names, out-of-range, mixed signs and wrong logical length. Ticket 10 should reuse it, and `subset_slots()` (an independent copy without raw, no category removal) is the base for `adata[i, j]`.
- `raw[i, j]` gives the Raw a parent that is a `subset_slots()` copy on observations.
- Python quirk kept: a Raw made without `X` (including `adata$raw <- other` with `other$X` NULL) is built from the parent.
- Deviation: `raw$X` and `raw$var` are assignable (validated) so `adata$raw$var$col <- v` works, Python modifies them in place.
- Zero indices error rather than being dropped as base R does.
