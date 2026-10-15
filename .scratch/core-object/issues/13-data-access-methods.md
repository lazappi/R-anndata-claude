# to_df, obs_vector, var_vector and key methods

Status: ready-for-agent
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
