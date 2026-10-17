# Lazy seeds spike

Status: in-progress
Type: research
Blocked by: none

## What

Choose the DelayedArray seeds for `lazy` (see the decisions in `.scratch/lazy/spec.md`).
Compare, for h5ad and zarr (v3 and v2) where they apply:

- HDF5Array's generic seeds: `HDF5ArraySeed` (dense) and `H5SparseMatrixSeed` (CSR/CSC groups).
  Do not use `H5ADMatrix` (ADR 0001).
- ZarrArray (Bioconductor, built on Rarr): whether it works with the Rarr devel version we use, v3 sharding and consolidated stores, and whether it covers anndata's zarr sparse groups (it likely does not)
- Our own seeds on the store layer's selection reads (zarr-io/02) and the backed classes (`backed`)

For each, record a verdict for: every On-disk dtype (int and uint widths, int64 and uint64, float32, h5py's bool enum, strings) read with the same values and dtype records as `read_h5ad()`/`read_zarr()`, block and random-access reads, chunk grids matching Python's default `chunks`, sparse results staying sparse, realisation cost, dependencies, and consistency with the backed classes.
Also check that an `S4Vectors::DataFrame` with DelayedArray columns (and a small lazy factor-like class) subsets, prints and realises naturally, as the starting point for lazy `obs`/`var`.

Scripts and their output live under `.ralph/oracle/` (git-ignored), and only the findings document is committed.

## Acceptance criteria

- A findings document at `.scratch/lazy/seeds-spike.md` with a verdict for every item and candidate, and a recommendation for the seeds and for lazy `obs`/`var`
- `scripts/check.sh` passes

## Comments

2026-10-17: Wrote `.scratch/lazy/seeds-spike.md` (HDF5Array seeds, ZarrArray, own seeds, `DataFrame` with DelayedArray columns).
- ZarrArray 1.1.7 was not installed, and `BiocManager::install("ZarrArray")` installed it into the user library for the spike (it is not a package dependency)
- Recommendation is own seeds on the store layer (dtype records, 2^53 rule, bool, sparse zarr, one path with backed), and a `DataFrame` with DelayedArray columns plus small categorical and nullable classes for `obs`/`var`
- Unresolved: an own seed over a zarr v3 store raised Rarr's `subscript out of bounds` on a block read although the same selections pass in `array_read()` directly. The checkpoint or the first implementation ticket must find the cause
- The store layer lacks a backend-neutral array shape and chunk shape, which seeds need
- `scripts/check.sh` passed (docs only change). The reviewer returned FAIL because the own-seed verdicts are incomplete, so the ticket stays `in-progress`
- Remaining for the next run (also in `fix_plan.md`): (1) find the cause of the zarr block-read error in `probe-own.R` (the failing Rarr call received an index mapping that does not match the direct `array_read()` call, so log the exact `selection` and Rarr `index` that fail) and give verdicts for zarr v3 and v2, (2) probe the own seed for every dtype, bool, the nullable and string columns, the 2^53 error, a CSR/CSC sparse seed and chunk shape, (3) probe `H5SparseMatrixSeed` for the 2^53 case and result types on sparse, and ZarrArray on sparse bool
