# to_df, obs_vector, var_vector and key methods

Status: done
Type: task
Blocked by: 06, 08

## What

Methods from the spec table (`anndata.py:946-1000`, `:1284`, `:1325`, `:1356`).

- `to_df(layer = NULL)` returns a dense `data.frame` and errors on duplicate names where R requires uniqueness
- `obs_vector(k, layer = NULL)` and `var_vector(k, layer = NULL)`
- `obs_keys()`, `var_keys()`, `obsm_keys()`, `varm_keys()`, `uns_keys()`

## Acceptance criteria

- Each method is tested including its documented errors
- `scripts/check.sh` passes

## Comments

2026-10-15: Added `to_df()`, `obs_vector()`, `var_vector()` and the `*_keys()` methods (`R/data-access.R`, `R/anndata.R`, `tests/testthat/test-data-access.R`).
New classes: `anndata_key_error`, `anndata_ambiguous_key_error`, `anndata_missing_x_error` (to_df with no X), `anndata_names_not_unique_error` (duplicate or NA obs_names in `to_df`, because R row names are unique).
Duplicate var_names are kept as column names.
Vectors from a variable use X or `layer`, and an obs/var column ignores `layer`.
Python's deprecation warnings on these methods are not reproduced (recorded in fix_plan Discovered).
