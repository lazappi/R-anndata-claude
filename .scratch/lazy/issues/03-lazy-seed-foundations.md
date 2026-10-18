# Seed foundations

Status: done
Type: task
Blocked by: none

## What

What the spike found is needed first: a backend-neutral `array_info()` giving shape and chunk shape for HDF5 and zarr arrays, and a seed `type()` fixed from the On-disk dtype record (see `.scratch/lazy/seeds-spike.md`).

## Acceptance criteria

- `array_info()` matches the on-disk shape and chunking for every h5ad and zarr fixture array
- `scripts/check.sh` passes

## Comments

2026-10-18: `array_info()` rows now carry list columns `shape` and `chunks` (numpy order) for h5 (`h5_shape_chunks()` in `R/dtype.R`) and zarr (`zarr_inner_chunks()`: inner chunk shape of a sharded v3 array, `chunks` of v2, `NULL` for contiguous HDF5 and 0-d arrays).
`h5_tree.py` and `zarr_tree.py` now report `chunks` (comparison helpers ignore it) and `test-io-store-info.R` checks shape and chunks of every h5ad and zarr (v3, v2) fixture array against Python.
Fixing a seed's `type()` from the dtype record needs a seed class, so it is done in tickets 04 and 05 (the 04/05 seeds must use `drop_dtype`/dtype of the array, not a probe read, since small h5ad int64/uint32/uint64 selections come back `integer`).
