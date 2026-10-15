# Subsetting

Status: ready-for-agent
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
