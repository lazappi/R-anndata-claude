# Backed mode

Status: needs-triage

Stub spec, to be grilled into a full spec before tickets are written.
Sub-project 7 of the roadmap (`.scratch/roadmap/spec.md`).

## Goal

`read_h5ad(file, backed = "r"/"r+")` returns an `AnnData` whose X stays on disk, matching Python's backed mode.

## Scope

- `backed = "r"`, `"r+"` and `TRUE`, `isbacked`, `filename`, file open and close, and the ` backed at '<file>'` repr suffix
- Backed dense X and backed sparse X (`sparse_dataset`, `CSRDataset`/`CSCDataset`), including subsetting reads
- `to_memory()`, `copy(filename)`, `chunked_X()` and `chunk_X()`
- `write_h5ad()` on a backed object (in-place update of X)
- `read_elem_partial`
- The setting `min_rows_for_chunked_h5_copy`

## Python references

- `src/anndata/_core/file_backing.py`, `src/anndata/_core/sparse_dataset.py`
- `src/anndata/_io/h5ad.py:184-213` (`read_h5ad_backed`)
- `src/anndata/_core/anndata.py:1002-1060`, `:1397-1446`, `:1832-1898`
- `src/anndata/abc.py`

## Open questions

- How should file handles be closed with R6 finalizers and rhdf5?
- Should backed arrays be DelayedArray-compatible, and how does that interact with `lazy`?
