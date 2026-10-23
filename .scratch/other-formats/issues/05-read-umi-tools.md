# read_umi_tools()

Status: done
Type: task
Blocked by: 01

## What

`read_umi_tools()`, with Python's category order for names.

## Acceptance criteria

- Every umi_tools row of the table passes
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: `R/io-umi-tools.R` reads the table itself (names sorted by radix order like pandas categories, duplicates summed, other columns ignored) and reuses `mtx_sparse()`.
With `dtype = NULL` X is int64 only if every count is an integer literal, else float64 (pandas column parsing, so `1.0` and `nan` give float64).
All 4 table rows pass (`tests/testthat/test-io-umi-tools.R`).
Empty and header-only files raise `anndata_invalid_value_error` like Python's errors.
Deviation: a row with a missing field raises `anndata_invalid_value_error`, where Python reads a missing last field as a NaN count (and fails with an obscure `ValueError` if two are missing).
