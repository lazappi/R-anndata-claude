# Dataframe

Status: ready-for-agent
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
