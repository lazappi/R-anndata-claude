# Dense arrays, string arrays, scalars, null and bytes

Status: done
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

2026-10-16: Done (`R/io-values.R`, tests in `test-io-values.R`).
- Scalar versus array is carried by `dim`: a scalar read has none, a 1-element array read has `dim` 1, and `as_array()` (exported) adds a `dim`
- Readers are now called as `fn(elem, path, store)` because rhdf5 cannot open a sibling dataset from a dataset handle (dtype needs `h5ls` of the parent)
- Files that call `register_*()` at top level must collate after `io-registry.R` (hence the name `io-values.R`)
- `find_writer()` looks up the class of `drop_dtype(value)`, so records do not hide the class
- `NA_real_` is normalised to NaN in `write_dataset()`
- Integer, logical and character `NA` raise `anndata_io_registry_error` until ticket 06 adds the nullable encodings (06 must replace that check in `write_values()`)
- `bytes` reads as a `raw` vector. Python's own rewrite turns integer and float32 scalars into int64 and float64 and cannot write a complex scalar, so the R -> Python -> R test accounts for that
- complex128 is written by taking the type from a throwaway dataset made with `h5createDataset(storage.mode = "complex")`, since rhdf5 has no exported compound builder
- `dataset_kwargs` (compression, chunking) is ignored for now and belongs to ticket 11, so scalars are trivially uncompressed
- Ticket 09 must strip the length-1 `dim` when reading dataframe columns from `read_elem()` values
- New fixtures `array_int32_min` and `scalar_int32_min`, plus `tests/python/rewrite.py`
