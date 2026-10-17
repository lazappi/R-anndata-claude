# Views: creation, access and Views of Views

Status: done
Type: task
Blocked by: 01

## What

`adata[i, j]` returns a View (spec "Behaviour"): the parent reference, normalised and composed indices, the lazy parts (X, layers, aligned mappings) and snapshot parts (obs, var, uns, raw), `is_view`, the `View of ` print prefix, `copy()` and reading without warnings.
Update existing tests that assumed subsets are copies only where the operations table shows Python returns a View.

## Acceptance criteria

- The reading and creation rows of the operations table pass, including Views of Views and parent changes after creation
- `scripts/check.sh` passes

## Comments

2026-10-17: `adata[i, j]` returns a View (`subset_view()` in `R/index.R`).
- Design: the View is built eagerly by `subset_anndata()` then marked with `mark_view(parent, oidx, vidx)`. `private$.view` holds the parent and positions, composed against the original parent for Views of Views. `X` is subset from the parent on each read, and `layers`/`obsm`/`varm`/`obsp`/`varp` are reloaded from the parent on each access (`refresh()`, `mapping$load()`). obs, var, uns and raw stay snapshots.
- Modification hook: `ensure_actual()` (public, internal) refreshes the mappings and clears `.view`. It is called by every setter, `strings_to_categoricals`, `rename_categories` and the mapping mutators (`touch()`). It does NOT warn yet, so ticket 03 must add Python's warnings and conditions (for example no-op assignments, `obs_assign`/`var_assign`/names setters that change the View without warning, `uns_nested` and `obs_col_del` quirks in the table). Raw mutation on a View is not hooked either (03).
- Internal calls must use `.subset2(mapping, "load")` because a key named `load` hides the method through `$`.
- Deviation to document in 05: Python's `parent_uns_nested` row (nested uns shared with the parent) cannot hold in R, the View's uns is a plain snapshot.
- `transpose()` of a View still returns a transposed copy (04 must raise Python's `ValueError`).
