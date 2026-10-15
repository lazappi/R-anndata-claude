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

## Open questions

- Which R lazy array framework fits best (e.g. DelayedArray with an HDF5 seed, or a custom one)?
  Python uses dask, which is a roadmap non-goal, so the R equivalent must be chosen.
- What should stand in for xarray `Dataset2D` in R?
- How does lazy reading relate to `backed`?
