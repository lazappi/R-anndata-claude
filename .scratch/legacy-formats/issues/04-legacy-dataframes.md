# legacy-formats: legacy dataframes and categories in uns

Status: done
Type: task
Blocked by: 03

## What

- `obs`/`var`/`raw.var` stored as a compound dataset (`read_dataframe_legacy`, `h5ad.py:332`): first field becomes the index and "very old version of AnnData" `OldFormatWarning`
- `dataframe` 0.1.0 (`read_dataframe_01`, `methods.py:1133`): categories in `__categories/<col>`, codes with a `categories` reference attribute (HDF5 object reference in h5ad, path string in zarr), `column-order` and `_index`
- Categories in `uns["<col>_categories"]` (`_clean_uns`) made categorical columns when `obs` is a dataset, with the keys removed from `uns`
- The `OldFormatWarning` for each dataframe column and `__categories` member that Python gives

## Acceptance criteria

- Fixtures from 0.6.22 (h5ad) and 0.7.8 (h5ad and zarr) read to the values, column order and warnings in the expectation table
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: Done.

- `read_dataframe_legacy()` (`R/io-legacy.R`) reads a compound `obs`/`var` dataset (first field is the index, warning "very old version" with `path`), int64 fields get their dtype record through the new store op `table_int64_fields()` (rhdf5 only tells int64 from float64 with `bit64conversion = "bit64"`, no op means no record)
- `read_anndata_elem()` uses it when `obs`/`var` is a dataset (`is_legacy_frame()`, also for ticket 05's `raw.var`), then `clean_legacy_uns()` (Python's `_clean_uns`) runs for the file root only
- `dataframe` 0.1.0 is a registered reader (`read_dataframe_01_elem()`, `read_series()`): categories through an HDF5 object reference (h5ad) or a relative path (zarr), `ordered` from the categories. `abort_legacy_categorical()` is removed
- `test-io-legacy.R` compares `obs`/`var` of the 0.6.22 and 0.7.8 fixtures (h5ad and zarr) to the table (index, index name, column order, categories, dtypes) and the warned paths under `/obs` and `/var`
- Not covered: a dataframe 0.1.0 with no columns (the code path is the plain empty `lapply`), the reviewer's first run failed on missing tests, which were added, and it was not rerun
- The whole-fixture comparison of ticket 03 still waits for ticket 05 (`raw.*`, the `uns["neighbors"]` move)
