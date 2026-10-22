# legacy-formats: legacy dataframes and categories in uns

Status: needs-triage
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
