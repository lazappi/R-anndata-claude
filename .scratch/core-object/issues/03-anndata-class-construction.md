# AnnData class and basic construction

Status: ready-for-agent
Type: task
Blocked by: 01, 02

## What

The exported `AnnData()` function wrapping an `AnnData$new()` R6 class (ADR 0002), with obs, var, shape inference and read-only fields (`anndata.py:244-517`, `:1965-2000`).

- Arguments after `uns` should be named
- `X` is stored in `layers` under the `NA` key and `adata$X` aliases it (ADR 0004), with the same validation however it is set.
  This ticket creates the internal layers storage, and ticket 06 exposes it as the `layers` mapping by extending that storage, not replacing it.
- Shape comes from `X`, `shape` or is inferred from the other Slots, and giving both `shape` and `X` is an error
- obs and var are built with the ticket 02 helpers
- Read-only fields: `n_obs`, `n_vars`, `shape`, `is_view` (always `FALSE`), `isbacked` (always `FALSE`), `filename` (always `NULL`)
- `filename` and `filemode` arguments error with a "not yet supported" condition
- Duplicate-name warning after construction when `check_uniqueness` is on
- `b <- a` aliases

## Acceptance criteria

- Construction from `X` (each matrix type), from `NULL` X with `shape`, and with inference
- Default names are `"0"`...`"n-1"`
- Every error and warning on these paths is tested by class
- Reference semantics test for aliasing
- `scripts/check.sh` passes

## Comments
