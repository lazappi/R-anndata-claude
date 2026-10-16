# Reading zarr v2

Status: ready-for-agent
Type: task
Blocked by: 08

## What

Read every v2 fixture through `read_zarr()` and `read_elem()`, including `.zmetadata` consolidated metadata, blosc compression and the v2 string and fill value differences the spike found.

## Acceptance criteria

- Python → R passes for every v2 fixture, and Python → R → Python passes with R writing v3
- `scripts/check.sh` passes

## Comments
