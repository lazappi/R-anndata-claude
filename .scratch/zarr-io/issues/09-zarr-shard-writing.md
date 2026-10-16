# Writing sharded zarr v3

Status: done
Type: task
Blocked by: 08

## What

Write sharded v3 arrays: the `sharding_indexed` codec with a `crc32c` index, `auto_shard_zarr_v3` with a 1 GB uncompressed target, and an explicit `shards` dataset argument (spec "Versions, sharding and consolidated metadata").

## Acceptance criteria

- R-written sharded stores read in Python and in R, for dense and sparse Elements and strings
- With default settings, R-written v3 stores are sharded like Python's (shard shapes need not match)
- `scripts/check.sh` passes

## Comments

2026-10-17: Done.
Arrays are written as before (inner chunk files), then `zarr_shard_files()` repacks the chunk files into shard files (chunks, a 16-byte-per-chunk index with 2^64-1 for missing chunks, and the `crc32c` of the index, index at the end) and `zarr_write_array_meta()` wraps the codecs in `sharding_indexed`.
`zarr_layout()` picks the shard shape: the whole array rounded up to whole chunks, reduced along the leading dimensions to stay within 1 GB uncompressed.
An explicit `shards` reduces the chunk shape to a divisor, and `shards = NULL` switches off the auto setting as in Python.
0-d arrays are not sharded and zero-length arrays are (only metadata), both as in Python.
`shards` applies to every array of `write_zarr()`, as Python's `ds_kwargs` do, so a shape only fits when all arrays have that rank (use `NULL` or the auto default otherwise).
`shards = "auto"` is rejected (Python accepts it), a possible later addition.
rec-arrays (`R/io-store-zarr-table.R`) are not sharded.
The crc32c is our own R table implementation, tested against the check string and zarr's index vectors.
Python reads R's sharded stores through the existing `Python -> R -> Python` fixture tests, which are sharded now by default.
