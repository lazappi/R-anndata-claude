# obs_names_make_unique and var_names_make_unique

Status: ready-for-agent
Type: task
Blocked by: 07

## What

Modify names in place following `make_index_unique` exactly (`src/anndata/utils.py:226-292`, `anndata.py:1578-1589`).

- `join = "-"` argument
- Counter algorithm, skipping `NA`, and the collision warning

## Acceptance criteria

- Results match Python for cases with collisions, `NA` and custom `join`, using committed Python-generated expectations
- Warning classes tested
- `scripts/check.sh` passes

## Comments
