# Concat table

Status: done
Type: task
Blocked by: none

## What

Write `tests/python/concat_cases.py` and generate the expected behaviour table (spec "Expected behaviour table"), with a hash-based freshness test.

## Acceptance criteria

- The table covers every combination listed in the spec
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-22: Wrote `tests/python/concat_cases.py` (one Python run, ~200 cases) and `tests/testthat/fixtures/concat_cases.json`, registered in `scripts/regenerate-fixtures.sh` and `generator_inputs()`, with `test-concat-table.R` (freshness, well-formedness, coverage of the spec's combinations).
The JSON has `inputs` (every input object described in full, so R rebuilds them) and `cases` (`name`, `inputs`, `args`, then `result` or `error`, plus `warnings`).
`args$named` means "pass a named list with these names", and `merge`/`uns_merge` of `"first_fn"` is a custom function returning the first element.
Facts the table records that later tickets must match:

- results are never CSC (CSC inputs come back as CSR) and float32 mixed with int32 gives float64
- an outer join of bool X reindexes to float64, and bool annotation columns are promoted to nullable `boolean` (Python 0.13.3)
- `keys_wrong_length` and `not_anndata` record accidental pandas and `AttributeError` errors, so R decides deliberately what to raise
- `scripts/regenerate-fixtures.sh` also repacks `zarr-fixtures.tar.gz` (bytes only differ)
