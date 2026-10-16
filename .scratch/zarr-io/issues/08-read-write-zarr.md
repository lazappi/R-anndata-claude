# read_zarr, write_zarr and settings

Status: done
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

2026-10-17, part 2 (done): dataset arguments of `write_zarr()`.
`compressors` is `NULL` (none), a name, or `list(name =, level =)` / `list(name = "blosc", cname =, clevel =, shuffle =)`, default zstd, applied to arrays, strings and scalars.
The `null` Element always gets zstd (Python ignores the kwargs there).
`compressor` is accepted as the older name and wins over `compressors`, as in Python (a numcodecs object is a `TypeError` in Python, we have none), and scalars ignore it (`legacy_compressor` marker) as `_remove_scalar_compression_args` does.
Unknown names (`compression`, `foo`, unnamed) raise `anndata_invalid_argument_error` (Python's `TypeError`).
`shards = NULL` is accepted (unsharded), any other value raises `anndata_not_supported_error` until ticket 09.
Python's `AnnData.write_zarr()` rejects these kwargs, ours forwards `...` (a superset).
Rarr's gzip is zlib, not gzip, which Python rejects, so gzip chunks are written uncompressed by Rarr and gzipped in R (`zarr_gzip_chunks()`).
Rarr ignores zstd levels, so the level is only recorded in the metadata.
Tests in `test-io-zarr-anndata.R`, with Python decoding every compressor.

2026-10-17, part 3 (done): `read_elem()`/`write_elem()` on zarr groups with paths now have tests in `test-io-zarr-basic.R` (absolute keys, `"/"`, forward slashes, registry error), the review found that Python always rejects `/` in keys for a zarr group (`registry.py:394-400`), so `write_elem()` now does too, whatever `disallow_forward_slash_in_h5ad` says.
`unwriteable(store_type = "zarr")` was already tested against Python in `test-io-h5ad.R`.
Python's `zarr_write_format = 2` DeprecationWarning is emitted when writing v2, so it belongs to ticket 11 (R refuses v2 until then).
The settings help text still says shards are not written, ticket 09 updates it.
NEWS mentions compression.
Status set to done.
