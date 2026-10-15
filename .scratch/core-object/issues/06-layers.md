# Layers

Status: done
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

2026-10-15: Layers are now the `AnnDataAlignedMapping` class with `attrname = "layers"` and X lives in it under `NA`, so `adata$X` and `adata$layers[[NA]]` share one store. Python-confirmed (`.ralph/oracle/layers.py`):
- Key order is insertion order: `X` goes last when given with layers (`c("a", NA)`), `X <- NULL` then `X <- v` appends it, and an `NA` entry in `layers` keeps the input position
- `adata$layers <- list(...)` (also `list()` and `NULL`) keeps X, appended last, with `anndata_future_warning` unless the list has an `NA` entry (`NA = NULL` drops X without warning)
- `clear(keep_x = NULL)` warns with `anndata_future_warning` and keeps X
- Wrong shapes are `anndata_dimension_error` with no reshape, and a 1-D vector becomes a column first, as in Python's base `_validate_value`
- More than 2 dimensions warns `anndata_non_2d_warning` for named layers only, as X warns in its own setter
- Data frames become matrices
- The constructor takes X from `layers[[NA]]`, errors if both differ, and infers the shape from layers
Tests that check state after a warning must use `expect_warning()`, because `expect_anndata_condition()` unwinds before the assignment completes.
