# write_csvs()

Status: ready-for-agent
Type: task
Blocked by: 01

## What

`write_csvs()` and `adata$write_csvs()` (spec "Scope"), including Views.
Mark the Views table's `write_loom` rows as out of scope (deprecated in Python, see the spec) instead of deferred.

## Acceptance criteria

- Every `write_csvs` row of the table and of the Views table passes
- Files written by R and Python are equal when pandas reads them back
- The full check (`scripts/check.sh --package` and `--tests`) passes
