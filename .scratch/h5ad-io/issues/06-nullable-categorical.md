# Nullable and categorical arrays

Status: done
Type: task
Blocked by: 05

## What

Register `nullable-integer`, `nullable-boolean`, `nullable-string-array` (all 0.1.0) and `categorical` 0.2.0.

- `factor` and `ordered`, categories keep their dtype and codes use the smallest integer dtype Python would use
- Categorical with missing values and with numeric categories
- `NA` handling and the `allow_write_nullable_strings` rule per the encoding table
- Fixtures for each

## Acceptance criteria

- All three round-trip directions pass for each fixture
- `scripts/check.sh` passes

## Decisions (human, 2026-10-15)

- Honour `allow_write_nullable_strings` as Python does: with `FALSE`, string arrays without missing values are written as `string-array`, and with missing values the write raises Python's error (fixtures `df_col_str_allow_nullable_false` and `df_col_str_na_allow_nullable_false`)

## Comments

2026-10-16: Done.
- `R/io-values-nullable.R` and `R/io-values-categorical.R` register the readers and writers. `write_values()` in `R/io-values.R` chooses the nullable Element (integer, logical or character with `NA`, or a value carrying the `anndata_nullable` record).
- The `anndata_nullable` record (`set_nullable()`/`get_nullable()` in `R/dtype.R`) restores `nullable-*` of values without `NA`. For strings it holds `na-value`.
- A factor keeps non-string categories in the `anndata_categories` attribute and writes them back only while the levels still match. `[` on a factor drops it, so categories are then written as strings.
- Code dtype is chosen from the level count (int8 below 127, int16 below 32767, else int32).
- `allow_write_nullable_strings = FALSE` with `NA` raises `anndata_nullable_strings_error`.
- New element-level fixtures `nullable_*` and `categorical_*` (and `nullable_str_*_allow_nullable_false`), encoding table regenerated.
- Dataframe columns (ticket 09) must mark `character` columns with `set_nullable(x, "NaN")` so they are written as `nullable-string-array` even without `NA`.
