# Sparse lazy seeds

Status: done
Type: task
Blocked by: 04

## What

A sparse DelayedArray seed for CSR and CSC groups on h5ad and zarr, built on the backed sparse class, staying sparse through SparseArray, with Python's default chunks (1000 rows for CSR, 1000 columns for CSC) and the `chunks` argument.

## Acceptance criteria

- Realised values equal `read_h5ad()`/`read_zarr()` for every sparse fixture, and results stay sparse
- `scripts/check.sh` passes

## Comments

2026-10-18: Implemented `StoreSparseSeed` (`R/lazy-sparse.R`, tests in `test-lazy-sparse.R`): a DelayedArray seed wrapping a `backed_sparse` over the store (so `backed_sparse_read()` serves h5ad and both zarr versions), `is_sparse()` TRUE, `extract_sparse_array()` giving an `SVT_SparseMatrix` of the dtype-fixed `type()`, `chunkdim()` per Python (major axis 1000 or `chunks`, minor axis whole, Python's two error messages), and `store_sparse_values()` with the data dtype record. SparseArray added to Imports.
Realised values equal `read_elem()` for every sparse fixture on all formats.
Index dtype records (`indices`/`indptr`) are not kept by a block, which is rebuilt over int32 indices, so the test compares the data dtype and values only.
An axis of length 0 has a chunk of 0 as in Python (DelayedArray rejects a chunk larger than the dimension). `StoreDenseSeed` still forces a minimum of 1 in `resolve_lazy_chunks()` and would hit that error for an empty dense array, see Discovered.
Internal, so no NEWS entry.
