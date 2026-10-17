# Lazy seeds spike

Status: ready-for-agent
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
