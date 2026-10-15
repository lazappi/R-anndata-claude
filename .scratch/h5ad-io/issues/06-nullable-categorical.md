# Nullable and categorical arrays

Status: ready-for-agent
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
