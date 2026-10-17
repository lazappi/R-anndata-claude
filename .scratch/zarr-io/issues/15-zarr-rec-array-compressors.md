# zarr rec-array compressors

Status: ready-for-agent
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
