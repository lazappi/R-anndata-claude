# Backed sparse X and sparse_dataset()

Status: ready-for-agent
Type: task
Blocked by: 02

## What

The backed sparse class for CSR and CSC, `sparse_dataset()`, partial reads of `data` and `indices`, every R index form, conversion to a `Matrix` sparse matrix in the same format, and Views of backed objects.

## Acceptance criteria

- The sparse rows of the operations table pass, and every R index form matches the in-memory selection
- `scripts/check.sh` passes

## Comments
