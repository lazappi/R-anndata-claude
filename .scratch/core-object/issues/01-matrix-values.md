# Matrix value coercion and helpers

Status: ready-for-agent
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
