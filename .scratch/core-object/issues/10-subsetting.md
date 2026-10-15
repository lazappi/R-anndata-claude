# Subsetting

Status: done
Type: task
Blocked by: 06, 08

## What

`adata[i, j]` returns an independent copy (`anndata.py:292-353`, `:1093-1117`, `:1377-1396`).

- R indexing: 1-based positions (repeats and reordering allowed), negative exclusion, full-length logical, character names (first match for duplicates)
- Errors for unknown names, out-of-range positions, `NA` and mixed-sign integers
- Missing `i` or `j`, and `adata[i]` for observations only
- Dimensions are never dropped
- Each Slot is subset as the spec "Subsetting" section lists, including obsp on both dimensions, raw on observations only and uns unchanged
- Unused factor levels removed per the `remove_unused_categories` setting, with `uns[["<col>_colors"]]` subset to match
- Sparse format and dtype metadata preserved
- `Raw` subsetting reuses the same index logic

## Acceptance criteria

- Positive, negative, logical and character indices tested on each axis
- Every Slot checked after subsetting
- Category removal tested with the setting on and off
- Duplicate names: first match is used
- `scripts/check.sh` passes

## Comments

2026-10-15: Added `[.AnnData` and `subset_anndata()` in `R/index.R` on top of the existing `subset_slots()`.
Raw is subset on observations only by passing a `raw` list to `AnnData()`.
`drop_unused_categories()` follows Python `_remove_unused_categories`: colors of the wrong length are removed, otherwise subset to the kept levels.
A length-1 colors entry is not special-cased because R has no 0-d arrays.
Tests in `tests/testthat/test-subsetting.R`.
