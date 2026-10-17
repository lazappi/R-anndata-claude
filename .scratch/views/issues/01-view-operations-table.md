# View operations table

Status: done
Type: task
Blocked by: none

## What

Write `tests/python/view_cases.py` and generate the expected behaviour table (spec "Expected behaviour table"), registered in `scripts/regenerate-fixtures.sh` with a freshness test.
Use `python-oracle` to find every operation that warns, copies or changes `is_view` in Python 0.13.4.

## Acceptance criteria

- The table covers every operation listed in the spec, and its freshness test passes
- `scripts/check.sh` passes

## Comments

2026-10-17: Added `tests/python/view_cases.py` (registered in `scripts/regenerate-fixtures.sh`) writing `tests/testthat/fixtures/view_cases.json`, and `tests/testthat/test-views.R` (freshness and coverage tests).
- Layout: `parent`, `view` and `view_of_view_start` (initial summaries), `operations` (on `parent[[0, 2], [0, 2]]`), `view_of_view` (the same operations on a View of a View, except `parent_*`), `composition` (chained index composition)
- Each row has `warnings` (category and message), `error`, `result`, `is_view_after`, `view_changed`/`view_after` (null if unchanged), `parent_changed`/`parent_after`
- The script fails if a public `AnnData` name is neither an operation nor in `NOT_OPERATIONS`
- Quirks Python shows that later tickets must match or decide on: `uns_nested` (`view.uns["nested"]["k"] = ...`) does not warn, does not copy and changes the parent. `obs_col_del`/`var_col_del` and `obs_assign`/`var_assign`/names setters change the View without warning. `obs_col_item` gives a pandas `ChainedAssignmentError`. `contains` with a string raises `TypeError`. `transpose` of a View raises `ValueError`.
- Layers are serialised with X under the key `"None"`, map it to the `NA` key in R
