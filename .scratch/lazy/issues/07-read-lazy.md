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

2026-10-18: Part 2 started, `read_lazy(store, load_annotation_index = TRUE)` in `R/lazy-read.R`, exported with the experimental badge.
`read_anndata_elem()` consults `read_state$lazy` and `read_lazy_slot()` returns lazy X, layers, obsm, varm, obsp, varp, obs and var (raw goes through the same reader), while uns stays eager.
`as_anndata_matrix()` now accepts any `DelayedArray` of the right dimensionality, and a `LazyDFrame` with `NULL` row names (`load_annotation_index = FALSE`) gets the dummy range names `"0"`... without the implicit-modification warning.
`lazy_small_paths()` moved to `helper-lazy.R`.
Tests in `test-lazy-anndata.R` (h5ad and zarr v3: slot classes, realised values, obsm/varm/obsp/raw, dummy index, argument errors).
Reviewer said FAIL on coverage, still to do: compare against the `read_lazy` table rows (`default`, `load_annotation_index_*`, `open_handle`, `missing_store`, `unconsolidated_zarr` with its warning), zarr v2 fixtures, a missing zarr directory, dtype checks, and decide/record the deviation that arrays inside `uns` are eager here (Python keeps them lazy).
