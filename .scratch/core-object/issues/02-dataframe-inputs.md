# obs and var data frame handling

Status: done
Type: task
Blocked by: none

## What

Internal helpers that turn user input into the `S4Vectors::DataFrame` held in obs and var (ADR 0003), following `src/anndata/_core/aligned_df.py:36-100` and `anndata.py:752-830`.

- Accept `NULL`, `data.frame`, `DataFrame` and named lists, including the `obs_names`/`row_names` and `var_names`/`col_names` elements as the index
- Default names `"0"` ... `"n-1"`
- Length mismatch with the shape raises a dimension error
- Non-character names are coerced to character with `anndata_implicit_modification_warning`
- Names may contain duplicates and `NA`
- The index name is preserved
- Factor and ordered columns are kept, and `NA` is preserved in every column type
- `S4Vectors` is added to Imports, replacing its placeholder line
- Uniqueness check helper that raises `anndata_names_not_unique_warning` (`src/anndata/utils.py:298-305`), ignoring `NA`

## Acceptance criteria

- Every input form above is tested, with Python-confirmed warnings and errors by class
- The index name survives each conversion
- `scripts/check.sh` passes

## Comments

2026-10-15: Done in `R/annotation-frames.R` (`as_annotation_frame()`, `check_names_unique()`, `warn_names_not_unique()`) with tests in `test-annotation-frames.R`.
- The index name lives in `S4Vectors::metadata(df)[["index_name"]]`, and is read from the `index_name` attribute of a `data.frame`. Later tickets must keep that metadata when copying, subsetting and transposing.
- `NA` row names need `with_frame_names()`, because `rownames<-` and `DataFrame(row.names=)` reject them.
- Python-confirmed: a frame with a default integer index warns and gets names `"0"`..`"n-1"` (R automatic row names behave the same way), and a wrong-length frame raises the `_mk_df_error` message.
- Deliberate deviation: Python's dict path keeps non-string `obs_names` (e.g. int64) with no warning, but the ticket and spec require coercion with `anndata_implicit_modification_warning`, so a list with non-character names warns.
- With no `expected` length, a list gets default names (Python overwrites the index), as in `aligned_df.py:66-67`.
