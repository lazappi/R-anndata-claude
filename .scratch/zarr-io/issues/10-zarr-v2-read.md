# Reading zarr v2

Status: done
Type: task
Blocked by: 08

## What

Read every v2 fixture through `read_zarr()` and `read_elem()`, including `.zmetadata` consolidated metadata, blosc compression and the v2 string and fill value differences the spike found.

## Acceptance criteria

- Python → R passes for every v2 fixture, and Python → R → Python passes with R writing v3
- `scripts/check.sh` passes

## Comments

2026-10-17: Reading v2 for every non-struct encoding (consolidated `.zmetadata`, blosc, `|O` vlen-utf8 strings) already worked from the store layer (zarr-io/04), so the `v2` variant was added to the Python -> R loops of `test-io-zarr-basic.R`, `-compound.R` and `-anndata.R`.
Only rec-arrays failed, as v2 stores them as a structured dtype (a list of `[name, typestr]` pairs) and not a v3 `struct`.
`R/io-store-zarr-table.R` now reads those (`zarr_v2_struct_fields()`, `zarr_v2_unpack()` decodes a chunk by reading it as a `|u1` array with the same compressor), rejecting big-endian, non-C order and filters with `anndata_not_supported_error`.
Python -> R -> Python for whole objects now writes v3 from the v2 originals too (Structurally equivalent).
Edited-copy tests cover uncompressed, missing-chunk and the error branches.
