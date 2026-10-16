# read_zarr, write_zarr and settings

Status: in-progress
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

2026-10-17, part 1 (done): `R/io-zarr.R` has `read_zarr()`, `write_zarr()` (v3, with `chunks`, `convert_strings_to_categoricals`, `consolidate_metadata`) and `adata$write_zarr()`.
Settings `zarr_write_format` (2 is refused with `anndata_not_supported_error`) and `auto_shard_zarr_v3` (flag only, no effect yet).
A missing `raw` is written as a `null` Element in zarr.
`write_zarr()` clears an existing store but refuses a non-empty directory that is not a zarr group.
`...` dataset arguments raise `anndata_not_supported_error` until part 2.
`read_zarr()` raises the legacy error for `raw.X`.
Tests: `test-io-zarr-anndata.R` (three round-trip directions and both cross-format directions on the whole-AnnData fixtures).
Python quirk: its `read_zarr` returns `raw = None` for a Raw with no observations, so those cases are left out of the tests where Python reads the store.
`tests/python/compare.py` and `rewrite_h5ad.py` now accept zarr stores (a `.zarr` output converts between formats).
`adata_fixture_names` and `r_built_adatas()` moved to `helper-io.R`.
Remaining parts are sub-items in `fix_plan.md`.
