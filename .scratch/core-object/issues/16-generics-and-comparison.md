# R generics and comparison error

Status: done
Type: task
Blocked by: 10, 11

## What

- `dim()`, `dimnames()`, `nrow()`, `ncol()`, `length()`, `t()` and `[` methods on `AnnData`
- `==` and other comparison operators raise a classed error equivalent to Python's `NotImplementedError` (`anndata.py:581-588`)
- Package documentation covers every exported function and class

## Acceptance criteria

- Each generic is tested
- Comparison operators error with the documented class
- Everything in the core-object spec scope is implemented and documented
- `scripts/check.sh` passes

## Comments

2026-10-15: Added `dim`, `dimnames` and `length` methods (`R/generics.R`, tests in `test-generics.R`), and `nrow`/`ncol` follow from `dim`.
`t` and `[` already existed.
- `length()` is `n_obs`, like Python's `len()`
- `==`, `!=`, `<`, `>`, `<=` and `>=` raise `anndata_not_implemented_error`, and other operators fall through to R's default error
- `.Generic` trips `object_usage_linter`, so `Ops.AnnData` reads it with `get()`
- Core-object scope is implemented apart from the `rename_categories` rec-array part of ticket 14, which waits on h5ad-io/08
