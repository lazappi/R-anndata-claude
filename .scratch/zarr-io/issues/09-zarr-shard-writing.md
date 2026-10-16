# Writing sharded zarr v3

Status: ready-for-agent
Type: task
Blocked by: 08

## What

Write sharded v3 arrays: the `sharding_indexed` codec with a `crc32c` index, `auto_shard_zarr_v3` with a 1 GB uncompressed target, and an explicit `shards` dataset argument (spec "Versions, sharding and consolidated metadata").

## Acceptance criteria

- R-written sharded stores read in Python and in R, for dense and sparse Elements and strings
- With default settings, R-written v3 stores are sharded like Python's (shard shapes need not match)
- `scripts/check.sh` passes

## Comments
