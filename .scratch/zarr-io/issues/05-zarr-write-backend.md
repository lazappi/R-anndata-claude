# Writing zarr stores

Status: ready-for-agent
Type: task
Blocked by: 02, 03

## What

The zarr backend for writing: Rarr plus our own writer layer (spec "zarr library").

- Groups and attributes (including array-valued and JSON-object attributes)
- Numeric and bool arrays with the On-disk dtype always given explicitly, int64 and uint64 from doubles
- Variable-length UTF-8 string arrays and 0-d arrays as Python writes them (see the zarr encoding table)
- v3 only in this ticket, unsharded, with Python's default codecs (`bytes` then `zstd`)
- Consolidated metadata writing

## Acceptance criteria

- Every array kind written by R reads back in Python with the same values, dtype and shape, and in R
- `scripts/check.sh` passes

## Comments
