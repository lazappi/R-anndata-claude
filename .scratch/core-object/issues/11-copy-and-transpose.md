# copy and transpose

Status: ready-for-agent
Type: task
Blocked by: 06, 08

## What

`copy()` (`anndata.py:1447`) and `transpose()`/`t(adata)` (`anndata.py:1248`).

- `copy()` is a deep copy independent of the original, and `filename` errors until `backed`
- `transpose()` swaps obs/var, obsm/varm and obsp/varp, transposes X and layers, drops raw and keeps uns
- Sparse format and dtype metadata are preserved by both
- The index names are preserved

## Acceptance criteria

- Reference semantics test: `b <- a` aliases and `a$copy()` does not
- Sparse format and dtype metadata survive both operations
- `scripts/check.sh` passes

## Comments
