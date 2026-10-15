# Remaining construction forms

Status: done
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

2026-10-15: Added `X` as an `AnnData` (Slots reused, other Slot arguments error with `anndata_invalid_argument_error`) and `X` as a `data.frame`/`DataFrame` in `R/anndata.R`.
Frame names become obs_names and var_names. Automatic row names count as Python's `RangeIndex` and are ignored.
Given obs/var with no names of their own (no index element, automatic row names or `NULL` row names) take the names of X, otherwise they must match or an `anndata_invalid_argument_error` is raised.
Mixed column types warn with `anndata_implicit_modification_warning` (Python `UserWarning`), and non-numeric columns fail through the usual matrix coercion.
Tests are in `tests/testthat/test-construction-forms.R`.
