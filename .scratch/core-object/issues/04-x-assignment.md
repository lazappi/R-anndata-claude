# X assignment and validation

Status: needs-triage
Type: task
Blocked by: 03

## What

Setting `adata$X` validates and coerces as Python does (`anndata.py:617-661`).

- Vector or 1-column/1-row matrix accepted when one dimension is 1
- Scalar fills the matrix and raises `anndata_future_warning`
- 2-D value of the wrong shape but the right size is reshaped with `anndata_future_warning`
- Other shapes error
- More than 2 dimensions warns
- `adata$X <- NULL` removes X
- The same rules apply to the constructor and to `adata$layers[[NA]]`

## Acceptance criteria

- Each branch above is tested by condition class, with Python-confirmed behaviour
- Sparse format is preserved on assignment
- `scripts/check.sh` passes

## Comments
