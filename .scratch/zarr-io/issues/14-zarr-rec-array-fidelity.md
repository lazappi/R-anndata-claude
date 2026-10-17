# zarr rec-array field dtypes and sharding

Status: ready-for-agent
Type: task
Blocked by: none

## What

The spec ("Encodings", rec-array rule) says zarr rec-arrays keep their field dtypes when zarr makes that easier than HDF5.
It does: `R/io-store-zarr-table.R` packs the v3 `struct` records itself, but zarr-io/07 wrote them with the ADR 0005 degradation (int32, float64 and `fixed_length_utf32` fields).

- Read a v3 `struct` rec-array keeping each field's On-disk dtype (an On-disk dtype record per field, like the records for plain arrays), and write it back with the same field dtypes, string kinds and widths
- An R-built rec-array with no records writes the field types Python would write for the equivalent values
- Write rec-arrays sharded under `auto_shard_zarr_v3` and accept `shards = "auto"`, as Python does
- HDF5 is unchanged (ADR 0005 and h5ad-io/15)

## Acceptance criteria

- zarr v3 rec-array fixtures are Structurally equivalent after every round-trip direction, with no rec-array exemption for zarr
- `scripts/check.sh` passes

## Comments
