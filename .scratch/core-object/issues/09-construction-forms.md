# Remaining construction forms

Status: needs-triage
Type: task
Blocked by: 06, 07, 08

## What

The construction paths not covered earlier (`anndata.py:396-436`).

- `X` as an `AnnData`: its Slots are used and any other argument errors
- `X` as a `data.frame` or `DataFrame`: row and column names become obs_names and var_names when obs and var are not given, and must match when they are
- The frame must be homogeneous (`ensure_df_homogeneous`, `src/anndata/utils.py`)
- All Slot arguments together: uns, obsm, varm, obsp, varp, layers and raw

## Acceptance criteria

- Construction from every accepted input form is tested, including the error cases by class
- `scripts/check.sh` passes

## Comments
