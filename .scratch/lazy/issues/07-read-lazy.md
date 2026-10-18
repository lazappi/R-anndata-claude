# read_elem_lazy and read_lazy

Status: in-progress
Type: task
Blocked by: 05, 06

## What

`read_elem_lazy()` and `read_lazy()` on h5ad and zarr with the lifecycle "experimental" badge, and the operations on lazily read objects: subsetting, Views, `to_memory()`, printing and writing to h5ad and zarr.

## Acceptance criteria

- Every row of the lazy operations table passes
- `scripts/check.sh` passes

## Comments

2026-10-18: Part 1 done, `read_elem_lazy(store, path = "/", chunks = NULL)` in `R/lazy-read.R`, exported with the experimental badge.
`store` is a path (h5ad file or zarr directory) or an open handle, because R has no element object like h5py's (a deviation from Python's `elem` argument).
A path to an h5ad is opened read-only and the handle carries a `closer` attribute whose finalizer closes the file.
Dense and sparse Elements are `DelayedArray`s, string, categorical and nullable Elements are lazy columns, `dataframe` is a `LazyDFrame`, anything else raises `anndata_io_registry_error`.
Build seeds before passing them to `DelayedArray()` (`delayed_seed()`), otherwise S4 dispatch wraps their errors in a `simpleError`.
Tests: `test-lazy-read.R` (chunk rows and error rows from the table, small AnnData written from R as h5ad and zarr v3, per-case fixtures for v2).
Remaining parts are in `fix_plan.md`: `read_lazy()` (lazy AnnData) and the operations rows.
