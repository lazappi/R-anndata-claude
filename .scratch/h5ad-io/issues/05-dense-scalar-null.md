# Dense arrays, string arrays, scalars, null and bytes

Status: needs-triage
Type: task
Blocked by: 03, 04

## What

Register `array` 0.2.0, `string-array` 0.2.0, `numeric-scalar` 0.2.0, `string` 0.2.0, `null` 0.1.0 and read-only `bytes` 0.2.0.

- Numeric, integer, logical and complex vectors, matrices and arrays, with shape equal to R `dim()`
- Scalars versus arrays rules, including the exported helper `as_array()` and remembering the Encoding type of an Element read from disk
- Scalars are never compressed
- Add fixtures for every numeric dtype as dense array and scalar to `tests/python/generate_fixtures.py`

## Acceptance criteria

- Python → R, Python → R → Python and R → Python → R pass for each fixture (see "Round-trip tests" in the spec)
- Scalar versus array behaviour is tested in both directions
- `scripts/check.sh` passes

## Comments
