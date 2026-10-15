# On-disk dtype preservation mechanism

Status: done
Type: task
Blocked by: 02, 03, core-object/01, core-object/10, core-object/11

## What

Implement the mechanism from "On-disk dtype preservation": record the On-disk dtype on read where R's native type differs (float32, int8, int16, int64, unsigned ints, sparse index dtypes) and restore it on write.

- Values no longer representable raise a classed error naming the path, and are never truncated or wrapped
- The record survives subset, copy and transpose from `core-object` and is invisible to arithmetic and printing
- 64-bit integer policy from the encoding table
- Helper used by every encoding ticket below

## Acceptance criteria

- Tested for vectors, matrices and arrays of every dtype
- Survival through subset, copy and transpose is tested
- Overflow on write errors with the documented class
- `scripts/check.sh` passes

## Decisions (human, 2026-10-15)

- int64 and uint64: read as double when every value has magnitude below 2^53, otherwise a classed error naming the path.
  `bit64` is not a dependency.
- An int32 dataset containing -2147483648 (R's `NA_integer_` bit pattern) is read as double with an int32 record, so it writes back unchanged and is never silently `NA`
- rec-array fields have no dtype records (ADR 0005)

## Comments

2026-10-16: done. `R/dtype.R` holds the mechanism:

- Record is the `anndata_dtype` attribute: a dtype name for dense values, a named vector `data`/`indices`/`indptr` for sparse. Plain vectors and arrays also get S3 class `anndata_typed` (print method hides the record), so `set_dtype()`, `get_dtype()`, `drop_dtype()` and `copy_dtype()` are the only way to touch it. Code checking `is.object()` must allow `typed_class`.
- `read_dataset(loc, name)` reads numeric datasets and records the dtype when it differs from R's (`integer` = int32, `double` = float64). It needs the parent group via `h5ls`, because rhdf5 cannot give a dataset's sign from its handle. A dataset-valued reader gets only `elem`, so ticket 05 must call `read_dataset(<store>, path)` with a group or file handle (absolute path works), e.g. by passing the store through the registry.
- `write_dataset(loc, name, x, scalar, dcpl)` writes with `write_dtype()` (record or native) after `check_dtype_fits()`. Overflow, NA, fractions in integer dtypes and float32 range errors are `anndata_dtype_overflow_error` with `path` and `dtype`.
- `sparse_write_dtypes(x, path)` gives the three sparse dtypes, honouring `write_csr_csc_indices_with_min_possible_dtype`, and checks each part (path `<path>/data` etc).
- Logical (bool) values are not handled here, the bool and nullable tickets own them.
- Read errors for 64-bit values >= 2^53 use the same overflow class. int32 with -2^31 is read as double (NA from rhdf5 mapped back).
- Tests: `tests/testthat/test-dtype.R`, including an h5py check of shape and dtype via `h5_tree.py`. Value orientation relies on the spike's aperm technique and is not checked by h5py here.
