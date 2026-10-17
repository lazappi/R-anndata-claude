# zarr rec-array field dtypes and sharding

Status: done
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

2026-10-17: Done.
- Field dtype records: numeric names (`"uint8"`, `"float32"`, ...) and strings as `"<type>:<length_bytes>"` (only when not the `fixed_length_utf32` width that writing would pick). Writing restores them, widens a recorded string width if values no longer fit, and raises `anndata_dtype_overflow_error` for values outside a numeric record.
- R-built fields get Python's types: int32, float64, bool (logical, no longer degraded to int32 in zarr) and UTF-32 of 4 x the longest UTF-8 byte length. Zero-row rec-arrays are writable in zarr (HDF5 still refuses).
- **Deviation from the ticket text:** Python 0.13.4 does not shard rec-arrays under `auto_shard_zarr_v3` (the call is commented out in `write_recarray_zarr`, `methods.py:763-766`), it only shards when `shards` is passed. We follow Python: sharded only with explicit `shards` (`"auto"`, a shape), and `shards = "auto"` is now accepted for every array. Reading handles `sharding_indexed` structs (index at the end only).
- `compressors` has no effect on rec-arrays (the struct reader only decodes zstd), Python honours it. Not done, candidates for a follow-up.
- Chunk shape is always one chunk (Python uses zarr's `guess_chunks`), which is not compared.
- Cross-format tests via HDF5 keep the rec-array exemption since HDF5 loses the dtypes (ADR 0005). The R -> Python -> R test compares values only because a Python rewrite turns `S` fields into `U`.
