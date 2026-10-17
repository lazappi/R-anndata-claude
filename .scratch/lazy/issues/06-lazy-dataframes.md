# Lazy obs and var

Status: ready-for-agent
Type: task
Blocked by: 04

## What

Lazy categorical and nullable column classes and lazy `obs`/`var` as `S4Vectors::DataFrame`s with lazy columns (spec "Decisions"), including `load_annotation_index`.

## Acceptance criteria

- Lazy data frames subset, print and realise to exactly what `read_h5ad()`/`read_zarr()` give, for every dataframe fixture
- `scripts/check.sh` passes

## Comments
