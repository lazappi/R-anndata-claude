# Dense lazy seeds

Status: ready-for-agent
Type: task
Blocked by: 02, 03

## What

A DelayedArray seed for dense arrays on h5ad and zarr (v3 and v2), using the store layer's selection reads, with On-disk dtype records, the 64-bit policy and Python's default chunking.

## Acceptance criteria

- Realised values equal `read_h5ad()`/`read_zarr()` for every dense fixture, and block reads read only their blocks
- `scripts/check.sh` passes

## Comments
