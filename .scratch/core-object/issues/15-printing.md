# Printing

Status: done
Type: task
Blocked by: 06, 08

## What

`print(adata)` and `format(adata)` reproduce Python's `__repr__` (`anndata.py:562-579`).

- Slot order, quoting and separators follow Python's `iter_outer` order
- `layers` lists X as `None (.X)` in Python's key order
- Empty Slots are omitted
- Fixture cases are added to `tests/python/generate_fixtures.py` for the expected strings, and fixtures regenerated and committed

## Acceptance criteria

- Output matches Python for a set of objects covering every Slot
- `scripts/check.sh` passes

## Comments

2026-10-15: Added `format.AnnData` and `print.AnnData` (`R/printing.R`).
- Expectations come from `tests/python/repr_cases.py` (a separate JSON script, registered in `scripts/regenerate-fixtures.sh`, rather than `generate_fixtures.py`, since no h5ad file is needed) with a freshness test
- Python lists X last in `layers` (`'counts', None (.X)`), so R puts `None (.X)` last regardless of storage order
- `View of` and `backed at` prefixes are omitted until views and backed mode exist
- Not covered: control characters in keys (Python's `repr` escapes `\n` and `\t`)
