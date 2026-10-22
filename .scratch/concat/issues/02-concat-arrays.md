# concat: axes, joins and arrays

Status: ready-for-agent
Type: task
Blocked by: 01

## What

`concat()` with `axis` and `join` for X and layers: dense and sparse mixing, the result's sparse format and On-disk dtype, reindexing with `fill_value`, bool promotion to nullable boolean on outer joins, and objects with no X. Annotations may be minimal here (names only).

## Acceptance criteria

- Its rows of the concat table pass
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments
