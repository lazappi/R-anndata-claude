# read_elem_lazy and read_lazy

Status: ready-for-agent
Type: task
Blocked by: 05, 06

## What

`read_elem_lazy()` and `read_lazy()` on h5ad and zarr with the lifecycle "experimental" badge, and the operations on lazily read objects: subsetting, Views, `to_memory()`, printing and writing to h5ad and zarr.

## Acceptance criteria

- Every row of the lazy operations table passes
- `scripts/check.sh` passes

## Comments
