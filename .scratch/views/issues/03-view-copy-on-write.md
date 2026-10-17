# Views: copy-on-write

Status: done
Type: task
Blocked by: 02

## What

Copy-on-write for every assignment and deletion through a View, including nested forms, with Python's warnings (spec "Behaviour").
The parent is never changed.

## Acceptance criteria

- The modification rows of the operations table pass for every Slot
- `scripts/check.sh` passes

## Comments

2026-10-17: Copy-on-write with Python's warnings (`warn_view_modified()` in `R/conditions.R`, `ensure_actual(what, kind, call)` in `R/anndata.R`, mapping `touch()` in `R/aligned-mappings.R`). Tests are in `test-views.R`.
- Every setter validates first, then detaches, so a failed assignment leaves the View a View (Python's `X_assign_wrong_shape` and View of View rows). Mapping `set()` forces validation before `put()`.
- `strings_to_categoricals()` detaches (and warns) only when a column changes. Raw changes are silent and keep the View (the View's Raw is its own object, as in Python).
- Deviations for ticket 05 to document, because R cannot tell `view$obs$col <- x` from `view$obs <- x`:
  - `obs`, `var`, `uns` and `X` setters always warn, while Python is silent for `obs_assign`, `var_assign`, `uns_assign`, and `obs_col_del`/`var_col_del`/`uns_del` stay Views in Python
  - item assignment on X, layers and obsm says "Setting element", Python says "Trying to modify attribute"
  - `uns_nested` does not change the parent (R values are snapshots)
  - `obs_col_item` is a pandas `ChainedAssignmentError` in Python, in R `view$obs$num[1] <- v` detaches
- Still for 04: `transpose()` of a View must raise Python's `ValueError`.
