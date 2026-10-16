# zarr v3: nullable, categorical, dataframe, dict and rec-array Elements

Status: done
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

2026-10-16: rec-array done, ticket `done`.

- `R/io-store-zarr-table.R` adds `table_read`/`table_write` for the v3 `struct` type: records packed in R, zstd through Rarr (`zarr_unzstd()` is the inverse of `zarr_zstd()`), reading handles any chunk grid and missing chunks (zeros)
- Writing follows ADR 0005 (spec line 81): int32, float64 and `fixed_length_utf32` fields in one chunk. zarr has no ASCII limit, so `write_rec_array()` only applies it to HDF5
- Reading mirrors the h5 R types: int8/16, uint8/16, int32 as integer, uint32/int64/uint64 as double (2^53 or more raises), bool as logical
- `rec_array_int64_big` is left out of the round-trip loops (it cannot be read) and has its own overflow test
- `rec_array_values.py` only reads HDF5, so R-written zarr rec-arrays are checked by R reads and by Python rewriting them (R -> Python -> R)
- Not done: v2 structured dtypes (zarr-io/10 and 11). The ASCII rule keys on `inherits(store, "zarr_node")`, a backend capability flag would be tidier
