# concat: obs, var and merge strategies

Status: ready-for-agent
Type: task
Blocked by: 02

## What

obs and var (categoricals, index), `merge` and `uns_merge` with every strategy and custom R functions, `label`, `keys` (and named lists) and `index_unique`.

## Acceptance criteria

- Its rows of the concat table pass
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments
