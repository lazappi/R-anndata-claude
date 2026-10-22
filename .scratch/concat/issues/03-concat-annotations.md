# concat: obs, var and merge strategies

Status: done
Type: task
Blocked by: 02

## What

obs and var (categoricals, index), `merge` and `uns_merge` with every strategy and custom R functions, `label`, `keys` (and named lists) and `index_unique`.

## Acceptance criteria

- Its rows of the concat table pass
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-22: Added `merge`, `uns_merge`, `label`, `keys`, `index_unique` and named-list input to `concat()` (`R/concat-annotations.R`), with the table rows for obs, var, uns and the non-unique names warning passing (`test-concat-annotations.R`).
Facts for later runs:

- `table_anndata()` now builds obs, var and uns from the table (`table_column()`), and `run_concat_case()` handles `named`, `keys` and `"first_fn"` (R: `function(values) values[[1L]]`). Aligned mappings and raw are still missing from it (ticket 04)
- Merge strategies are `merge_nested()` over named lists, and `intersect_keys()` follows the order of the last mapping as Python's `OrderedSet &` does. `concat_equal()` is Python's `equal()`, with `same_type` for columns (`Series.equals`)
- Custom `merge` functions get the reindexed frames and may return a frame or named list, `uns_merge` functions get the `uns` lists
- Deviations: keys are converted to character, and columns Python would turn into mixed `object` columns (numbers with strings, bool with numbers) raise `anndata_unsupported_value_error`. A categorical with strings becomes a character column, as in Python
- Bad `merge`, `uns_merge`, `keys` (length, duplicates, with a named list) and `label`/`index_unique` raise `anndata_invalid_argument_error`
- `varm`/`obsm` values also go through `merge` in Python (`alt_mapping`), which ticket 04 must do with `resolve_merge_strategy()`
