# Matrix value coercion and helpers

Status: done
Type: task
Blocked by: none

## What

Internal helpers for the array values held in X, layers, obsm, varm, obsp and varp (spec "Representation").

- Accept base `matrix` (double, integer, logical), `dgCMatrix`/`lgCMatrix` and `dgRMatrix`/`lgRMatrix`
- Coerce other `Matrix` classes on assignment: sparse to CSC, dense to base `matrix`
- Axis-aware helpers that subset, transpose and report dimensions while preserving the sparse format (CSR stays CSR, CSC stays CSC)
- Subsetting and transposing keep On-disk dtype metadata where the values are kept (tested with a test double for the metadata)
- Support arrays with 2 or more dimensions where the spec allows them (obsm, varm, layers)
- `Matrix` is added to Imports, replacing its placeholder `@importFrom` line

## Acceptance criteria

- Each accepted class round-trips through the helpers unchanged
- Each coerced class becomes the documented target class
- Subsetting rows, columns and both preserves format and dtype metadata
- Unsupported values error with a classed condition
- `scripts/check.sh` passes

## Comments

2026-10-15: Added `R/matrix-values.R` with `as_anndata_matrix()` (validate/coerce, `allow_array` for 3+ dims), `matrix_dim()`, `matrix_subset(x, i, j)` and `matrix_transpose()`.
Errors use `anndata_unsupported_value_error`.
Matrix 1.x keeps CSR on `[` and `t()` here, but `matrix_transpose()` converts back to CSR explicitly as the spec requires.
The On-disk dtype record is the `anndata_dtype` attribute (internal constant `dtype_attr`), copied by `copy_dtype()`.
This is a test double, h5ad-io/04 may replace it and should change `copy_dtype()` only.
`methods` was added to Imports (needed for `methods::is`/`as`) and `Matrix` is now used through `@importClassesFrom` and `Matrix::t`.
Subsetting takes 1-based integer positions (or `NULL`), index resolution from R indices belongs to core-object/10.
