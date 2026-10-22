# concat: axes, joins and arrays

Status: done
Type: task
Blocked by: 01

## What

`concat()` with `axis` and `join` for X and layers: dense and sparse mixing, the result's sparse format and On-disk dtype, reindexing with `fill_value`, bool promotion to nullable boolean on outer joins, and objects with no X. Annotations may be minimal here (names only).

## Acceptance criteria

- Its rows of the concat table pass
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-22: Added `concat(adatas, axis, join, fill_value)` in `R/concat.R`, with names only for obs and var.
Tickets 03 and 04 add `merge`, `uns_merge`, `label`, `keys`, `index_unique` and `pairwise` to the signature.
Decisions and facts for later runs:

- Table rows used are those whose args are within axis, join and fill_value and that succeed (87 rows), plus the argument errors tested by hand (`anndata_invalid_argument_error`) and `anndata_missing_x_warning` for Python's "Some Xs are None" warning
- Shared test helpers (`table_anndata()`, `run_concat_case()`, `concat_cases_with_args()`, `expect_matches_table_array()`) are in `helper-concat.R`, and they build inputs with names only, so 03 and 04 must extend `table_anndata()` with annotations
- Arrays are combined in R as triplets/matrices with numpy's dtype promotion (`promote_dtype()`), canonical row-concatenation (var axis transposes in and out) and `fill_value` types: R integer is int64, double is float64, logical is bool
- Default fill is 0 when any input array is sparse, otherwise `NA`, and an `NA` fill counts as non-zero as in Python
- Outer-join names are sorted by code point unless all objects have equal names (pandas `Index.union`), and duplicates in alternate-axis names are dropped by `unique()` (unchecked against Python)
- Inputs must be in memory: backed and lazy X is for tickets 05 and 06
- Matrix `dimnames` do not become `obs_names` in `AnnData()`, so tests pass `obs`/`var` frames
