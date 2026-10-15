# Layers

Status: ready-for-agent
Type: task
Blocked by: 05

## What

The `layers` mapping including the X entry under `NA` (ADR 0004), following `aligned_mapping.py:349-386`.

- First two dimensions equal the shape, and more than 2 dimensions warns
- `adata$layers[[NA]]` and `adata$layers[[NA_character_]]` both address X
- `names()` and `as.list()` include `NA` for X in Python's key order (confirm with a Python-generated fixture)
- `adata$layers <- list()` and `adata$layers$clear()` keep X and raise Python's warning
- `clear(keep_x = TRUE/FALSE)` controls this explicitly

## Acceptance criteria

- Key order matches Python for several constructions
- Clearing behaviour and warning class match Python
- `scripts/check.sh` passes

## Comments
