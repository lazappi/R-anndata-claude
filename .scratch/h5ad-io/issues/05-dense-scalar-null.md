# Dense arrays, string arrays, scalars, null and bytes

Status: ready-for-agent
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

## Decisions (human, 2026-10-15)

- complex64 arrays and scalars raise a classed error naming the path on read, and only complex128 is written
- Apply the int32 -2147483648 rule from ticket 04 to arrays and scalars, with a fixture containing that value

## Comments
