# Other formats

Status: ready-for-agent

Sub-project 10 of the roadmap (`.scratch/roadmap/spec.md`).
Readers and writers for formats that cannot represent a full `AnnData`, matching Python's results.

Python references are relative to `.reference/anndata/src/anndata/`: `_io/read.py` (`read_csv:30`, `read_excel:60`, `read_umi_tools:94`, `read_hdf:117`, `read_mtx:336`, `read_text:366`, `_read_text`), `_io/write.py` (`write_csvs:30`) and `_core/anndata.py:1747` (the `write_csvs` method).

## Decisions (human, 2026-10-23)

- Loom is out: Python 0.13 deprecates `read_loom` and `write_loom` ("Loom isn't well-maintained and supports only a subset of anndata features").
  The Views table's `write_loom` rows stay deferred, marked `wontfix` (in our Python environment they record `ModuleNotFoundError` anyway).
- `read_excel()` uses readxl, in `Suggests` and checked with `rlang::check_installed()`, and openpyxl is added to the Python environment for the expected results.
  There is no Excel writer, as in Python.
- `dtype` arguments take numpy dtype strings (default `"float32"`, as Python), and values stay R doubles or integers carrying the On-disk dtype record, so a written result has Python's dtype
- `write_csvs()` output matches Python's when pandas reads both back: the same file names, header rows, index columns, names and values.
  Byte-identical files are welcome where cheap but not required (pandas writes floats with `repr`, R does not by default).
- `read_text()` and `read_csv()` take a path (plain, `.gz` or `.bz2`), a connection or a character vector of lines (R's equivalents of Python's iterator of lines)

## Scope

In:

- `read_csv()`, `read_text()`, `read_mtx()`, `read_umi_tools()`, `read_hdf()` and `read_excel()`, exported with Python's arguments and defaults
- `write_csvs()` as a function and as the `AnnData` method `adata$write_csvs()`, with its warnings (`WriteWarning` for sparse and unwritable `uns` values)
- The Views table rows for `write_csvs`

Out:

- `read_loom()` and `write_loom()` (deprecated in Python)
- Writing Excel, mtx, text or hdf (Python has no such writers)

## Behaviour

- Every result, warning and error follows Python, as recorded in the table below
- `read_text()`'s header and row-name detection (`first_column_names = NULL`, comment lines, whitespace splitting when `delimiter = NULL`) follows `_read_text`
- `read_mtx()` returns CSR X as Python does, and `read_umi_tools()` sparse CSR with Python's category order for `obs` and `var` names
- Index types follow `restrict_index_types` where Python checks it (`read_excel`)

## Expected behaviour table

`tests/python/other_formats_cases.py` (registered in `scripts/regenerate-fixtures.sh`, with a hash-based freshness test like the other tables) writes the input files and a JSON table to `tests/testthat/fixtures/`.
Inputs cover at least: csv and text with and without header and row names, comment lines, whitespace and other delimiters, `.gz` and `.bz2`, mtx (coordinate and array, integer, real and pattern), umi_tools, hdf with and without `row_names`/`col_names` and with an empty key, and xlsx.
For each reader case it records the result's X (values, dtype, sparse format), names and any warning or error (class and message).
For `write_csvs` it records the files written (relative paths) and their contents as pandas reads them, for objects with dense and sparse X, `skip_data` both ways, a `.csv` dirname, another `sep`, and `uns` values that are sparse, scalar, nested or unwritable.
Keep Python starts to one script run.

## Required tests

- Every row of the table
- `write_csvs()` output read by pandas equals Python's output read by pandas
- The Views table rows for `write_csvs`

## Acceptance criteria

- Every row of the table and the Views `write_csvs` rows pass
- The full check (`scripts/check.sh --package` and `--tests`) passes
