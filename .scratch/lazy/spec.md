# Lazy arrays

Status: ready-for-agent

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

Second round (orchestrator, 2026-10-17, after the spike in `.scratch/lazy/seeds-spike.md`):

- Our own DelayedArray seeds, dense and sparse, for h5ad and zarr, built on the store layer's selection reads and the backed classes.
  HDF5Array and ZarrArray are not used: neither keeps On-disk dtype records, both fail on bool, and ZarrArray has no sparse groups and mishandles 64-bit values.
- Lazy `obs`/`var` are `S4Vectors::DataFrame`s with 1-d DelayedArray columns, plus small S4 classes for categorical (codes seed and categories) and nullable (values and mask) columns that define `length`, `[`, `show` and realisation (`as.vector`, `as.data.frame`)
- Lazy reading and `backed` share the seeds and the store layer, but stay separate APIs, as in Python: `backed` keeps X on an open h5ad file with a file manager, and `lazy` reads every Element lazily from h5ad or zarr

## Scope

In:

- `read_elem_lazy(elem, chunks = NULL)` and `read_lazy(store, load_annotation_index = TRUE)` on h5ad and zarr (v3 and v2), exported with a lifecycle "experimental" badge
- Dense and sparse (CSR and CSC) DelayedArray seeds with On-disk dtype records and the 64-bit policy of `read_h5ad()`, sparse results staying sparse (SparseArray)
- Python's default chunks (`(1000, n_vars)` for CSR, `(n_obs, 1000)` for CSC, the on-disk chunking for dense) and the `chunks` argument, mapped to the DelayedArray chunk grid
- Lazy categorical and nullable columns, and lazy `obs`/`var`, including `load_annotation_index`
- Operations on lazily read objects as in Python: subsetting and Views, `to_memory()`, printing, and writing to h5ad and zarr
- A vignette section

Out:

- dask-specific behaviour, and Python's xarray coordinates beyond what `load_annotation_index` needs

## Behaviour

- Realising any lazy value gives exactly what `read_h5ad()`/`read_zarr()` give for the same Element, including On-disk dtype records, factors and `NA`
- Reading a lazy object reads metadata only, and data is read when realised or block-processed
- Every operation, error and warning follows Python, as recorded in the operations table

## Expected behaviour table

`tests/python/lazy_cases.py` (registered in `scripts/regenerate-fixtures.sh`) writes a JSON table to `tests/testthat/fixtures/`, recording for each operation on a lazily read object (h5ad and zarr) the result, any error or warning, and, where Python exposes it, what is read.
Operations cover at least: `read_lazy()` with both `load_annotation_index` values, `read_elem_lazy()` of every encoding with default and explicit `chunks`, subsetting, Views, `to_memory()`, printing, and writing to h5ad and zarr.

## Acceptance criteria

- Every row of the lazy operations table passes
- Realised values equal `read_h5ad()`/`read_zarr()` for every fixture
- `scripts/check.sh` passes
