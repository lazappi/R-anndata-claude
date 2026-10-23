# read_text() and read_csv()

Status: ready-for-agent
Type: task
Blocked by: 01

## What

`read_text()` and `read_csv()` with paths (plain, `.gz`, `.bz2`), connections and character vectors of lines, following `_read_text`.

## Acceptance criteria

- Every text and csv row of the table passes
- The full check (`scripts/check.sh --package` and `--tests`) passes
