# read_mtx()

Status: ready-for-agent
Type: task
Blocked by: 01

## What

`read_mtx()`, returning CSR X with the requested dtype record.

## Acceptance criteria

- Every mtx row of the table passes
- The full check (`scripts/check.sh --package` and `--tests`) passes
