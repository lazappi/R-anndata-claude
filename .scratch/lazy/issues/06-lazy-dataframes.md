# Lazy obs and var

Status: done
Type: task
Blocked by: 04

## What

Lazy categorical and nullable column classes and lazy `obs`/`var` as `S4Vectors::DataFrame`s with lazy columns (spec "Decisions"), including `load_annotation_index`.

## Acceptance criteria

- Lazy data frames subset, print and realise to exactly what `read_h5ad()`/`read_zarr()` give, for every dataframe fixture
- `scripts/check.sh` passes

## Comments

2026-10-18: `R/lazy-columns.R` (`LazyCategorical`, `LazyNullable`, 1-d DelayedArray columns, `lazy_column()`) and `R/lazy-dataframe.R` (`LazyDFrame` contains `DFrame` with a `lazy_index` slot, `lazy_dataframe()`, `lazy_dataframe_realise()`, `as.data.frame()`).
Eager and lazy reads share `categorical_from_parts()`, `nullable_from_parts()` and `frame_from_parts()`, and `store_dense_seed(strings = TRUE)` accepts string arrays.
Decisions for ticket 07:
- `load_annotation_index = FALSE` gives `NULL` row names (Python's dummy range index) and keeps the true index as a lazy column in `lazy_index`, which row subsetting follows and realising loads
- Row subsets of lazy columns keep On-disk dtype records, eager `DataFrame` subsets drop them, so tests compare after `drop_dtype()`
- `lazy[, "a"]` of a one-column frame drops to the column as for any `DataFrame`, use `drop = FALSE`
- Added `BiocGenerics` to Imports (for the `as.vector`/`as.data.frame` S4 methods)
Not tested: the column-length mismatch error in `lazy_dataframe()` (needs an edited fixture).
