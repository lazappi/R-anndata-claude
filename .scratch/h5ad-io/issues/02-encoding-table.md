# Encoding table

Status: needs-triage
Type: research
Blocked by: 01

## What

Build the encoding table described in "Choosing an encoding on write" by writing each equivalent Python value from the reference environment and recording the Encoding type, Encoding version, On-disk dtype and HDF5 attributes for each R value class.
Cover every row of the spec's encoding table, the dataframe column rules (string, nullable, categorical, `allow_write_nullable_strings`), index handling, `column-order`, categorical code dtype choice, `logical` with and without `NA`, `integer` with `NA`, NaN handling, complex values, and scalar versus array.
Decide the int64 policy if the spike did not.

## Acceptance criteria

- `.scratch/h5ad-io/encoding-table.md` is committed and every row is observed from Python 0.13.4, not assumed
- The table lists the fixture case name for each row
- `scripts/check.sh` passes

## Comments
