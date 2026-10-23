# read_hdf()

Status: ready-for-agent
Type: task
Blocked by: 01

## What

`read_hdf()`, including `row_names`/`col_names` and the empty-key error.

## Acceptance criteria

- Every hdf row of the table passes
- The full check (`scripts/check.sh --package` and `--tests`) passes
