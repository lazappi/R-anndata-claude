# Seed foundations

Status: ready-for-agent
Type: task
Blocked by: none

## What

What the spike found is needed first: a backend-neutral `array_info()` giving shape and chunk shape for HDF5 and zarr arrays, and a seed `type()` fixed from the On-disk dtype record (see `.scratch/lazy/seeds-spike.md`).

## Acceptance criteria

- `array_info()` matches the on-disk shape and chunking for every h5ad and zarr fixture array
- `scripts/check.sh` passes

## Comments
