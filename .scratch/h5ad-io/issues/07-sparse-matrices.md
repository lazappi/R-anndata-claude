# Sparse matrices

Status: ready-for-agent
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
