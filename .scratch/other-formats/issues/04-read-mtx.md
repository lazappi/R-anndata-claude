# read_mtx()

Status: done
Type: task
Blocked by: 01

## What

`read_mtx()`, returning CSR X with the requested dtype record.

## Acceptance criteria

- Every mtx row of the table passes
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: `R/io-mtx.R` parses Matrix Market itself (coordinate and array, real, integer, pattern, general/symmetric/skew-symmetric/hermitian), sums duplicates then casts like scipy, and records the dtype on a `dgRMatrix`.
All 11 table rows pass (`tests/testthat/test-io-mtx.R`).
Complex fields raise an error because scipy's behaviour (complex128 cast with a `ComplexWarning`) was not checked, see fix_plan Discovered.
