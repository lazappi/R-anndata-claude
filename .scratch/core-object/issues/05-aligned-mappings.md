# Aligned mappings: obsm, varm, obsp, varp

Status: done
Type: task
Blocked by: 03

## What

R6 mapping objects for obsm, varm, obsp and varp (`src/anndata/_core/aligned_mapping.py:288-310`, `:440-465`).

- Support `[[<-`, `[[`, `$`, `names()`, `length()`, `as.list()` and `[[<-` with `NULL` to remove
- `adata$obsm <- list(...)` assigns a whole named list
- Axis arrays: first dimension equals n_obs (or n_vars), and a data frame value must have row names equal to the obs_names (or var_names)
- Pairwise arrays: both dimensions equal n_obs (or n_vars)
- Accepted values follow the spec "Representation" section, including arrays with 2 or more dimensions and `DataFrame`/`data.frame` for obsm and varm

## Acceptance criteria

- Every validation error is tested by class, with Python-confirmed conditions
- Values survive storage unchanged, including sparse format and dtype metadata
- `scripts/check.sh` passes

## Comments

2026-10-15: Implemented `aligned_mapping_class` (R6, `R/aligned-mappings.R`) behind `adata$obsm/varm/obsp/varp`, with S3 `$`, `[[`, `[[<-`, `$<-`, `names`, `length` and `as.list`.
Python behaviour confirmed with `.ralph/oracle/aligned.py`.
- `adata$obsm[["k"]] <- v` makes R assign the mapping back to `adata$obsm`, so the active binding ignores a value identical to the current mapping
- Whole-list assignment validates everything before replacing, as Python does
- A plain vector becomes a one column matrix, other values go through `as_anndata_matrix(allow_array = TRUE)`
- Frame values in axis arrays need row names equal to the names (automatic row names fail, as Python's RangeIndex does) and take the parent's index name
- `$` looks up keys first, then methods, so a key named like a method hides it and `[[` is always safe
- The constructor now accepts the four slots and infers the shape from them
Deliberate deviations: a data frame in obsp/varp errors (Python converts a homogeneous one to an array, the spec only allows matrices), and keys must be single non-empty strings (Python accepts any key, R lists cannot hold `NA` or empty names).
Ticket 06 can reuse the class: layers need their own kind (first two dimensions, non-2D warning, `NA` key, `clear(keep_x)`), so extend `aligned_kinds` and `validate`.
