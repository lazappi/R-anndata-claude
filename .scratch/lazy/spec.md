# Lazy arrays

Status: needs-triage

Stub spec, to be grilled into a full spec before tickets are written.
Sub-project 8 of the roadmap (`.scratch/roadmap/spec.md`).
Important, but after the MVP.

## Goal

Read Elements and whole `AnnData` objects lazily, so data is loaded only when accessed, matching Python's `read_elem_lazy` and `read_lazy`.

## Scope

- `read_elem_lazy()` and `read_lazy()`
- Lazy categorical and masked (nullable) arrays
- A lazy `obs`/`var` representation (Python uses xarray-backed `Dataset2D`)

## Python references

- `src/anndata/_io/specs/registry.py:439` (`read_elem_lazy`) and `src/anndata/_io/specs/lazy_methods.py`
- `src/anndata/experimental/backed/` (`read_lazy`, `MaskedArray`, `CategoricalArray`, `Dataset2D`)
- `src/anndata/_core/xarray.py`

## Decisions (human, 2026-10-17, first grilling round)

- DelayedArray is the lazy framework (no other R framework fits on-disk HDF5 and zarr arrays).
  A spike (lazy/01) compares existing seeds (HDF5Array's generic `HDF5ArraySeed` and `H5SparseMatrixSeed`, ZarrArray) with our own seeds built on the store layer's selection reads and the backed classes, and the orchestrator chooses after it, asking the human only if there is no clear choice.
  HDF5Array's `H5ADMatrix` is an h5ad reader and is not used (ADR 0001).
- Lazy `obs`/`var`: whatever works best, is easy for users and matches Python adapted to R.
  The starting point is an `S4Vectors::DataFrame` with lazy columns (1-d DelayedArrays, and small lazy categorical and nullable classes), confirmed by the spike.
- `read_lazy()` and `read_elem_lazy()` are exported with a lifecycle "experimental" badge, with Python's arguments (`load_annotation_index`, `chunks` mapped to the DelayedArray chunk grid)
- DelayedArray and SparseArray go in Imports (plus whatever the chosen seeds need)
- Expected behaviour comes from a Python-generated operations table, as for views and backed

## Open questions

- Which seeds to use (spike lazy/01)
- How does lazy reading relate to `backed`?
