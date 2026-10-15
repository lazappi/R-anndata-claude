# X assignment and validation

Status: done
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

2026-10-15: Implemented `coerce_x_shape()` in `R/anndata.R`, used by the `X` setter, with Python-confirmed behaviour (oracle script `.ralph/oracle/xset.py`):
- scalar fills with `anndata_future_warning`
- vector or 2-D value of the right size is reshaped in C (row-major) order with `anndata_future_warning`
- wrong size or sparse needing a reshape is an `anndata_dimension_error` (after the warning, as in Python)
- more than 2 dimensions with matching leading dims warns `anndata_non_2d_warning`, otherwise `anndata_dimension_error`
- `NULL` removes X
The constructor takes its shape from X so no mismatch arises, and a scalar X errors there as in Python.
Remaining: apply the same rules to `adata$layers[[NA]]`, which needs the layers mapping from ticket 06.
Python's `layers[None] = wrong shape` raises ValueError with no reshape and no warning, so ticket 06 should check that rather than reuse the X reshape.
Status stays `in-progress` until then.

2026-10-15: `adata$layers[[NA]]` assignment is done in ticket 06 (shape check with `anndata_dimension_error`, no reshape or warning, Python-confirmed), and all criteria are met.
