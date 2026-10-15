# Aligned mappings: obsm, varm, obsp, varp

Status: needs-triage
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
