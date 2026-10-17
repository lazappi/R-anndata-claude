# Writing zarr v2

Status: needs-info
Type: task
Blocked by: 10

## What

Write v2 stores when `zarr_write_format = 2`: `.zgroup`/`.zarray`/`.zattrs`, `vlen-utf8` string arrays, Python's default v2 compressor (blosc lz4 with shuffle) and `.zmetadata`.
If this turns out expensive, stop and ask: the human decided writing v2 may move to a follow-up ticket.

## Acceptance criteria

- All three round-trip directions pass for every v2 fixture
- `scripts/check.sh` passes

## Comments

2026-10-17: Stopped as the ticket asks ("if expensive, stop and ask").
Question: should writing v2 move to a follow-up ticket (after the MVP) or proceed now?
It looks expensive because `R/io-store-zarr-write.R` (about 1000 lines) is v3 only: every `zarr.json` is ours and Rarr writes only chunks.
v2 needs a second metadata writer (`.zgroup`, `.zarray`, `.zattrs`, `.zmetadata`), `.`-separated chunk keys, a hand-written `vlen-utf8` filter for string chunks, blosc lz4 shuffle chunks, structured-dtype rec-arrays (inverse of `zarr_v2_unpack()`), and no sharding.
Nothing was started.
Recommended answer: move it to a follow-up ticket, keep `zarr_write_format = 2` refused with a clear error for now, and finish zarr-io/12 (docs) first.
