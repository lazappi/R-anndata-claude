# Printing

Status: ready-for-agent
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
