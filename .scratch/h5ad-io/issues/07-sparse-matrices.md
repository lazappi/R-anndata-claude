# Sparse matrices

Status: done
Type: task
Blocked by: 04, 05, core-object/01

## What

Register `csr_matrix` and `csc_matrix` 0.1.0 for `dgRMatrix`, `lgRMatrix`, `dgCMatrix` and `lgCMatrix`.

- Every data dtype and index dtype, including min-dtype indices via `write_csr_csc_indices_with_min_possible_dtype` (`methods.py:867-968`)
- Shape attribute handling and empty matrices
- Fixtures for CSR and CSC for every numeric dtype

## Acceptance criteria

- All three round-trip directions pass for each fixture
- `scripts/check.sh` passes

## Comments

2026-10-16: Added `R/io-sparse.R` (writers for `dgCMatrix`, `lgCMatrix`, `dgRMatrix`, `lgRMatrix`, readers for `csr_matrix` and `csc_matrix`) and `tests/testthat/test-io-sparse.R`.

- `data`, `indices` and `indptr` are plain datasets with no Encoding attributes, so they use `write_dataset()`, `write_bool_dataset()` and `read_values()` directly, not `write_elem()`
- The On-disk dtype record holds only the components that differ from float64/bool, int32 and int32
- Indices and pointers are read as R integers, and values above the int32 maximum raise `anndata_dtype_overflow_error`
- Added fixtures for int16 and all unsigned dtypes, CSC int64 and min-dtype indices, and a 300-row CSC (`csc_wide`, uint16 indices), and regenerated the encoding table
- `dataset_kwargs` (compression) is accepted and ignored until ticket 11
- Complex sparse data has no `Matrix` class and is not supported
