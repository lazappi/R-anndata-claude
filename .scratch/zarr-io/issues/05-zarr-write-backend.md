# Writing zarr stores

Status: done
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

2026-10-16: done.

- `R/io-store-zarr-write.R` adds the write operations to `zarr_backend()` (v3 only, other versions raise `anndata_not_supported_error`): `group_create`, `member_delete`, `attr_write`, `dataset_write`, `bool_write`, `complex_write`, `string_write`, `null_write`, plus `zarr_create(path)` (root group of a new store) and `zarr_consolidate(path)`.
  `table_write` (rec-array) is left to zarr-io/07
- Metadata (`zarr.json`) is always written by us to match Python (explicit dtype, fill value, `bytes` then `zstd`, no identity `transpose` codec that Rarr adds with `order = "C"`), and Rarr writes the chunks of numeric and bool arrays
- Rarr cannot write 0-d arrays, vlen strings or 64-bit values from doubles.
  Scalars, strings and `null` encode the chunk bytes in R and compress them through Rarr by writing them as a 1-d uint8 array (its chunk file is exactly the zstd frame, the fill value must differ from the payload or Rarr skips the chunk).
  int64, uint64, the int32 minimum, big uint32 and complex are written as uint16 (or float64) parts with a trailing dimension and the chunk files are then moved to the real keys (the inverse of `zarr_split_read()`)
- `null` writes no chunk, as Python does (the value is the fill value).
  Missing `raw` is written as `null` by the caller (zarr-io/06 or later)
- Rarr's `zarr_consolidate_metadata()` output is rejected by Python (empty attributes written as lists), so `zarr_consolidate()` collects the metadata itself into the root `zarr.json` (inline, `kind` `inline`)
- Compression arguments in `dataset_kwargs` are ignored for now (every array gets `bytes` then `zstd`), ticket 08 owns them, and nothing is sharded (ticket 09)
- `zarr_attr_read()` now keeps named lists (JSON objects) as lists
- Chunk shape is at most 2^20 values per chunk, which need not match Python
- Python check: `tests/python/zarr_describe.py` now prints complex values as `[re, im]`
