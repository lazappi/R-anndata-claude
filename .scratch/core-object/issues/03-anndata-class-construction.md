# AnnData class and basic construction

Status: done
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

2026-10-15: Done in `R/anndata.R` (`AnnData()`, internal `AnnDataClass`, `infer_shape()`) with tests in `test-anndata-class.R`.
- The layers storage is `private$.layers`, a named list with X first under the `NA` name. Ticket 06 extends it.
- `adata$X` validates the shape exactly and coerces with `as_anndata_matrix()`. Ticket 04 adds vectors, scalars, reshaping and more than 2 dimensions (currently an unsupported-value error).
- `obs`, `var`, `obs_names` and `var_names` are read-only for now (`anndata_read_only_error`), ticket 07 adds assignment.
- `uns`, `obsm`, `varm`, `obsp`, `varp`, `layers` and `raw` arguments raise `anndata_not_supported_error` until tickets 05 to 09 so values are never dropped. `infer_shape()` already handles them, and is unit tested directly.
- `shape` with `X` and an invalid `shape` raise `anndata_invalid_argument_error`.
- `.lintr` now allows the names `AnnData`, `AnnDataClass` and `X` in `object_name_linter`.
- `AnnDataClass` needs `@noRd`, otherwise roxygen warns about a missing title, and `@importFrom R6 R6Class` must stay in the package file.
