# Other formats table

Status: done
Type: task
Blocked by: none

## What

Write `tests/python/other_formats_cases.py` and generate the input files and expected behaviour table (spec "Expected behaviour table"), with a hash-based freshness test.
Add openpyxl to the uv project in `tests/python`.

## Acceptance criteria

- The table covers every input and `write_csvs` case listed in the spec
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: Done.
- `tests/python/other_formats_cases.py` writes inputs to `tests/testthat/fixtures/other_formats/` and the table to `other_formats_cases.json` (registered in `scripts/regenerate-fixtures.sh` and `generator_inputs()`), openpyxl added to the uv project.
- `readers` rows: `name`, `reader`, `source` (`kind` `file` or `lines`), `args`, `warnings` and `result` (X with kind, format, dtype, shape, values, plus names, name dtypes, index names and columns) or `error` (class, message with the input directory stripped).
- `write_csvs`: `adatas` (described in full, `uns` entries have a `kind`) and `cases` (`adata`, `dirname`, `args`, `warnings`, `files` keyed by relative path with pandas-read `columns`, `index`, `values`, `dtypes` and raw `text`).
- Python's readers ignore `dtype` in `read_excel` (values are `object` for float sheets, `int64` when the first column is integer labels), `read_mtx` gives CSR float32 by default, errors for empty text are accidental `IndexError`s.
- `tests/testthat/test-other-formats-table.R` checks freshness, well-formedness and spec coverage.
- The Python file is not ruff-formatted (`ruff` is not allowlisted in loop runs), other tickets may format it.
