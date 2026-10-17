# Backed sparse X and sparse_dataset()

Status: in-progress
Type: task
Blocked by: 02

## What

The backed sparse class for CSR and CSC, `sparse_dataset()`, partial reads of `data` and `indices`, every R index form, conversion to a `Matrix` sparse matrix in the same format, and Views of backed objects.

## Acceptance criteria

- The sparse rows of the operations table pass, and every R index form matches the in-memory selection
- `scripts/check.sh` passes

## Comments

2026-10-17: Added `R/backed-sparse.R` (`backed_sparse` class, also `backed_x`, with `[`, `$` (`format`, `backend`, `to_memory()`), `as.matrix`, `as.array`) and exported `sparse_dataset(group, ..., should_cache_indptr)`, with table-driven tests in `test-backed-sparse.R`.
- `[` reads `indptr` (cached in `x$cache`), then only the `data` and `indices` slices of the selected rows (CSR) or columns (CSC), filters the minor axis in memory and rearranges repeated and unsorted positions in memory. It returns `dgRMatrix`/`lgRMatrix` (CSR) or `dgCMatrix`/`lgCMatrix` (CSC), or a vector when `drop` removes a dimension
- `read_sparse_elem()` now ends in `new_sparse_matrix()`, shared with the backed reader
- Python rejects or differs for some selections (CSR negative int, CSC negative column slice), R selects like a matrix and the tests say so
- `sparse_dataset()` takes an rhdf5 group handle and uses absolute paths from `node_path()`. Not-sparse input raises `anndata_invalid_argument_error`
- Remaining: `append()` and the h5sparse legacy attributes, listed as sub-items in `fix_plan.md`, so the ticket stays `in-progress`
