# zarr v3: dense, string, scalar, null and sparse Elements

Status: done
Type: task
Blocked by: 04, 05

## What

Register and test the basic encodings on zarr v3: `array`, `string-array`, `numeric-scalar`, `string`, `null`, `csr_matrix` and `csc_matrix`, including the zarr-specific differences (spec "Encodings").

## Acceptance criteria

- All three round-trip directions pass for the v3 fixtures of these encodings
- `scripts/check.sh` passes

## Comments

2026-10-16: done.

- The encodings already went through the store layer, so no registration was needed: `tests/testthat/test-io-zarr-basic.R` runs the three directions over every basic v3 fixture (v3, unsharded and unconsolidated variants for Python -> R)
- complex64 raises `anndata_dtype_error` as for h5ad, and Python cannot rewrite complex scalars
- Python widens numeric scalars on rewrite (`read_scalar` returns plain `int`/`float`, `methods.py:1362-1367`), also for h5ad, so R -> Python -> R compares their values only (noted in the zarr encoding table)
- Fixed: zarr member lookup was case-insensitive on macOS (`x` found `X`), now `zarr_node_exists()`
- `rewrite.py` and `python_rewrite(ext =)` accept zarr stores
- v2 is covered by tickets 10 and 11
