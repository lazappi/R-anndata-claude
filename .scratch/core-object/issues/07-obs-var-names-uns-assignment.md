# obs, var, names and uns assignment

Status: ready-for-agent
Type: task
Blocked by: 03

## What

Active bindings for obs, var, obs_names, var_names and uns (`anndata.py:752-830`, `:769-819`).

- `adata$obs <- df` and `adata$var <- df` convert as in construction, check the row count and keep current names unless the value brings its own
- `adata$obs_names <- x` and `adata$var_names <- x` check length, coerce to character and apply the uniqueness warning
- The index name is preserved
- `adata$uns <- list(...)` must be a named list or empty, and `adata$uns[["k"]] <- v` sets one entry

## Acceptance criteria

- Each branch is tested by condition class, with Python-confirmed behaviour
- `scripts/check.sh` passes

## Comments
