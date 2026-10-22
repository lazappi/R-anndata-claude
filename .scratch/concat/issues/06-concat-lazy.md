# concat: lazy inputs

Status: done
Type: task
Blocked by: 05

## What

Lazily read objects as inputs, kept lazy as Python does, with realised values equal to the in-memory result.
If a case cannot sensibly match Python, record it as a deviation in the ticket and the help page rather than blocking.

## Acceptance criteria

- Its rows of the concat table pass
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-22: The concat table has no lazy rows, so `test-concat-lazy.R` compares lazy results with the in-memory result (both axes, inner/outer, `fill_value`, dense and sparse, layers, obsm, raw, varm) and checks mixed lazy and in-memory inputs are in memory.
`concat_arrays()` keeps the result lazy (`concat_arrays_lazy()`: reindex by subsetting, `ConstantArray` fills, `S4Arrays::arbind`) when every input array is a `DelayedArray`, otherwise it reads them (`realise_lazy_value()`), as Python's `merge.py` does.
Deviations (also in the `concat()` help page): `obs`/`var` of lazy inputs are read into memory (Python keeps `Dataset2D`, which loses categoricals and raises `DTypePromotionError` on outer joins with string var columns), and lazy results have DelayedArray's R types rather than promoted On-disk dtypes.
Python's oracle scripts are in `.ralph/oracle/lazyconcat*.py`.
