# Sparse lazy seeds

Status: ready-for-agent
Type: task
Blocked by: 04

## What

A sparse DelayedArray seed for CSR and CSC groups on h5ad and zarr, built on the backed sparse class, staying sparse through SparseArray, with Python's default chunks (1000 rows for CSR, 1000 columns for CSC) and the `chunks` argument.

## Acceptance criteria

- Realised values equal `read_h5ad()`/`read_zarr()` for every sparse fixture, and results stay sparse
- `scripts/check.sh` passes

## Comments
