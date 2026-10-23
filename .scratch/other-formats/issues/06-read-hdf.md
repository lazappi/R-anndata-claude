# read_hdf()

Status: done
Type: task
Blocked by: 01

## What

`read_hdf()`, including `row_names`/`col_names` and the empty-key error.

## Acceptance criteria

- Every hdf row of the table passes
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: Added `read_hdf()` (`R/io-hdf.R`) using the store layer (`read_dataset()`, `string_read()`) with all seven table rows tested in `test-io-hdf.R`.
A missing key raises `anndata_key_error`, an empty key `anndata_invalid_value_error`.
Full check and tests pass.
