# Writing zarr v2

Status: ready-for-agent
Type: task
Blocked by: 10

## What

Write v2 stores when `zarr_write_format = 2`: `.zgroup`/`.zarray`/`.zattrs`, `vlen-utf8` string arrays, Python's default v2 compressor (blosc lz4 with shuffle) and `.zmetadata`.
If this turns out expensive, stop and ask: the human decided writing v2 may move to a follow-up ticket.

## Acceptance criteria

- All three round-trip directions pass for every v2 fixture
- `scripts/check.sh` passes

## Comments
