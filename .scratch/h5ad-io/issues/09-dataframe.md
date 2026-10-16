# Dataframe

Status: done
Type: task
Blocked by: 06, core-object/02

## What

Register `dataframe` 0.2.0 for `DataFrame` and `data.frame`.

- Index written as Python writes it, including `_index` attribute, index name, duplicate and `NA` names, non-ASCII names, and a column with the same name as the index
- `column-order` and every column type from the spec's fixtures list
- Fixtures for each

## Acceptance criteria

- All three round-trip directions pass for each fixture
- `scripts/check.sh` passes

## Decisions (human, 2026-10-15)

- Honour `allow_write_nullable_strings` for string columns and the index, as in ticket 06
- A `DataFrame` or `data.frame` with `NULL` row names is written with an int64 `array` `_index` of `0` to `n - 1`, as Python writes a `RangeIndex` (fixture `df_index_range`)

## Comments

2026-10-16: Added `R/io-values-dataframe.R` (reader and writer for `DataFrame` and `data.frame`) and `tests/testthat/test-io-dataframe.R`, which covers every `df_*` fixture in the three directions.
- A non-string index (int64, range, categorical) or a plain `string-array` index is kept in `metadata()$index_source` and written back while the row names still match.
- A string read from a plain `string-array` gets the nullable record `FALSE`, which `nullable_kind()` treats as "write a `string-array`", so those columns and indexes round trip.
- `df_col_str_allow_nullable_false` is skipped in the R -> Python -> R test only, because `rewrite.py` runs with Python's default setting and rewrites nullable strings.
  It is covered in the other two directions with the setting off.
- `expect_python_equal()` compares whole AnnData files, so it is not used for Elements.
