# read_zarr, write_zarr and settings

Status: ready-for-agent
Type: task
Blocked by: 07

## What

The public functions and settings (spec "Public functions" and "Versions, sharding and consolidated metadata").

- `read_zarr()`, `write_zarr()`, `adata$write_zarr()`, `read_elem()`/`write_elem()` on zarr groups and `unwriteable(store_type = "zarr")`
- `AnnData` and `Raw` Elements, `chunks`, dataset arguments (compression and `shards`), `convert_strings_to_categoricals` and `consolidate_metadata`
- The settings `zarr_write_format` and `auto_shard_zarr_v3` (until ticket 09, sharding is documented as not yet written)
- The realistic `gen_adata` fixture and the cross-format checks (h5ad to zarr and zarr to h5ad)
- Every error and warning from the spec, and NEWS entries

## Acceptance criteria

- All three round-trip directions pass for every v3 fixture, and the cross-format checks pass in both directions
- `scripts/check.sh` passes

## Comments
