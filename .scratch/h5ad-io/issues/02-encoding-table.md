# Encoding table

Status: done
Type: research
Blocked by: none

## What

Build the encoding table described in "Choosing an encoding on write" by writing each equivalent Python value from the reference environment and recording the Encoding type, Encoding version, On-disk dtype and HDF5 attributes for each R value class.
Cover every row of the spec's encoding table, the dataframe column rules (string, nullable, categorical, `allow_write_nullable_strings`), index handling, `column-order`, categorical code dtype choice, `logical` with and without `NA`, `integer` with `NA`, NaN handling, complex values, and scalar versus array.
This ticket only needs the Python reference environment, so it does not wait for the rhdf5 spike.
Decide the int64 policy if the spike has not, and reconcile with the spike's recommendation if both exist.

## Acceptance criteria

- `.scratch/h5ad-io/encoding-table.md` is committed and every row is observed from Python 0.13.4, not assumed
- The table lists the fixture case name for each row
- `scripts/check.sh` passes

## Comments

2026-10-15: Done.
- Added about 130 encoding cases to `tests/python/generate_fixtures.py` (files under `tests/testthat/fixtures/h5ad/`, an Element at key `x`, or a whole `.h5ad`), with `settings` variants and `errors` in the manifest for values Python refuses.
- `tests/python/encoding_table.py` generates the observed block of `.scratch/h5ad-io/encoding-table.md` from the fixtures, and a test fails when the committed block is stale. Rerun it after changing a case (command in the table header).
- `h5_tree.py` now handles the `null` encoding's null dataspace.
- **int64 policy decided:** read int64 and uint64 as `double` when every value is below 2^53 in magnitude, otherwise raise a classed error naming the path.
  `bit64` stays in Suggests. Writing int64 is restored through the on-disk dtype record.
- Findings the later tickets need: pandas 3 `str` columns and the obs/var index are written as `nullable-string-array` with `na-value='NaN'` (not `string-array`), categorical code dtype is int8 below 127 categories, int16 below 32767 and int32 otherwise, min-dtype sparse `indices` use the minor axis size, and Python cannot write nullable `Float64`.
