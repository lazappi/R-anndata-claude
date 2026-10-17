# zarr rec-array compressors

Status: done
Type: task
Blocked by: none

## What

zarr rec-arrays ignore the `compressors` dataset argument, because the v3 `struct` reader and writer (`R/io-store-zarr-table.R`) only handle zstd and always write one chunk.
Python honours `compressors` for rec-arrays.

- Read and write rec-arrays with every compressor `write_zarr()` supports for other arrays (zstd, gzip, blosc and none), and read Python-written rec-arrays compressed with each
- Keep sharding and field dtypes working (zarr-io/14)

## Acceptance criteria

- All three round-trip directions pass for rec-arrays with each compressor
- `scripts/check.sh` passes

## Comments

2026-10-17: Done.
The writer uses `zarr_compressor_arg()` and `zarr_compress()`, and the reader's `zarr_decompress()` handles zstd, gzip (in R), blosc and none, both plain and inside shards.
Blosc metadata records the record size as `typesize`.
`rec_array_basic` and `rec_array_widths` were added to the compressor variants of the zarr fixtures (archive regenerated, nothing else changed).
The unsupported-codec test now uses `crc32c`, as gzip is supported.
Full check passed in 6m05s (tests 641s CPU over 4 workers), still close to the limit (see Discovered in `fix_plan.md`).
