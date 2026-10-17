# Views: methods and writing

Status: ready-for-agent
Type: task
Blocked by: 03 (and zarr-io/08 for writing zarr)

## What

Every public method on a View follows the operations table (`transpose()` raises Python's error), and writing a View to h5ad and zarr writes the subset, Structurally equivalent to Python writing the same View.

## Acceptance criteria

- The method and I/O rows of the operations table pass
- `scripts/check.sh` passes

## Comments
