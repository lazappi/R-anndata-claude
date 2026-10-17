# Views: creation, access and Views of Views

Status: ready-for-agent
Type: task
Blocked by: 01

## What

`adata[i, j]` returns a View (spec "Behaviour"): the parent reference, normalised and composed indices, the lazy parts (X, layers, aligned mappings) and snapshot parts (obs, var, uns, raw), `is_view`, the `View of ` print prefix, `copy()` and reading without warnings.
Update existing tests that assumed subsets are copies only where the operations table shows Python returns a View.

## Acceptance criteria

- The reading and creation rows of the operations table pass, including Views of Views and parent changes after creation
- `scripts/check.sh` passes

## Comments
