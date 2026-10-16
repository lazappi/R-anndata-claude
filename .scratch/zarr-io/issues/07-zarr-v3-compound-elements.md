# zarr v3: nullable, categorical, dataframe, dict and rec-array Elements

Status: in-progress
Type: task
Blocked by: 06

## What

Register and test the remaining encodings on zarr v3: the nullable arrays, `categorical`, `dataframe`, `dict` and `rec-array` (spec "Encodings", including the rec-array rule).

## Acceptance criteria

- All three round-trip directions pass for the v3 fixtures of these encodings
- `scripts/check.sh` passes

## Comments

2026-10-16: part done, ticket stays `in-progress`.

- Nullable arrays, `categorical`, `dataframe` and `dict` already worked through the store layer, so `tests/testthat/test-io-zarr-compound.R` runs the three directions over their v3 fixtures (Python -> R also for the unsharded and unconsolidated variants)
- R -> Python -> R skips the `*_allow_nullable_false` cases, because Python's default settings rewrite plain strings as nullable (as for h5ad)
- `h5_case_elem()` moved to `helper-io.R`
- Remaining: `rec-array`.
  The zarr backend has no `table_read`/`table_write`, so `read_elem()` fails with "attempt to apply non-function".
  Python writes a v3 `struct` data type (fields with `int32`, `float64`, `null_terminated_bytes`, `fixed_length_utf32`, ...) with `bytes` + `zstd` codecs, and a v2 structured dtype.
  Rarr cannot read or write these, so they need our own chunk packing and unpacking (zstd is reachable through Rarr, see `zarr_zstd()` in `R/io-store-zarr-write.R`), and ADR 0005 versus Python's field dtype fidelity in zarr needs a decision (see Discovered in `fix_plan.md`)
