# read_text() and read_csv()

Status: done
Type: task
Blocked by: 01

## What

`read_text()` and `read_csv()` with paths (plain, `.gz`, `.bz2`), connections and character vectors of lines, following `_read_text`.

## Acceptance criteria

- Every text and csv row of the table passes
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: Done.
- `R/io-text.R` ports `_read_text` line by line, tests in `test-io-text.R` drive every `read_text`/`read_csv` row (values, dtype record, names, error class, and Python's message for `ValueError`s).
- A single string is a path, so one line of text is passed as `I("...")`, any other character vector is lines.
- Python's accidental `IndexError`s for input with no data lines become `anndata_invalid_value_error` with the clearer message "The text has no data lines.".
- Integer dtypes reject fractions and out of range values as numpy does (`text_numbers()`), floats are rounded with `to_float32()`.
- The Excel, mtx, umi_tools and hdf readers can reuse `typed_dense()` for the dtype record.
