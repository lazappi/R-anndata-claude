# read_excel()

Status: done
Type: task
Blocked by: 01

## What

`read_excel()` through readxl (in `Suggests`, checked with `rlang::check_installed()`).

## Acceptance criteria

- Every xlsx row of the table passes
- Tests skip cleanly without readxl
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: Added `read_excel()` (`R/io-excel.R`) with readxl read as `col_types = "list"` cells, tested against all eight table rows (`test-io-excel.R`, skipped without readxl) plus mocked odd sheets.
Deviations, documented in the help page: Python's `object` X (text in the first column) has no R form so R gives doubles (X is `int64` only if the whole sheet is whole numbers), names are always strings even with `restrict_index_types` off (the unrestricted row compares `as.character()` labels, since the package never keeps non-string indices), and `dtype` is ignored as in Python.
`sheet` is zero-based as in pandas.
The Python message for an out-of-range sheet position is from memory of pandas (not in the table).
