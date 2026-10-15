# strings_to_categoricals and rename_categories

Status: needs-triage
Type: task
Blocked by: 07

## What

`strings_to_categoricals(df = NULL)` (`anndata.py:1170`) and `rename_categories(key, categories)` (`anndata.py:1118`).

- Character columns with fewer unique values than rows become factors, in place on obs and var or on `df`, with Python's messages
- `rename_categories` renames factor levels and the `uns` entries Python renames

## Acceptance criteria

- Results and messages match Python using committed Python-generated expectations
- Errors tested by class
- `scripts/check.sh` passes

## Comments
