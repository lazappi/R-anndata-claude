# obs and var data frame handling

Status: ready-for-agent
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
