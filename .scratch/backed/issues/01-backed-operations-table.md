# Backed operations table

Status: done
Type: task
Blocked by: none

## What

Write `tests/python/backed_cases.py` and generate the expected behaviour table (spec "Expected behaviour table"), registered in `scripts/regenerate-fixtures.sh` with a freshness test.
Use `python-oracle` to find every operation that errors, warns or changes the file in Python 0.13.4.

## Acceptance criteria

- The table covers every operation listed in the spec, and its freshness test passes
- `scripts/check.sh` passes

## Comments

2026-10-17: Added `tests/python/backed_cases.py` (registered in `scripts/regenerate-fixtures.sh`, about 22s) writing `tests/testthat/fixtures/backed_cases.json`, and `tests/testthat/test-backed.R` (freshness and coverage tests).
- Layout: `operations[name][kind][mode]` (kind `dense`/`csr`/`csc`, mode `r`/`r+`), `raw_operations` (the subset that writes to the backing file, run on a file with `raw`), `in_memory[kind]`, `read_h5ad` (`backed=` values and constructor errors), `read_elem_partial`, `sparse_dataset` (including `append`) and `settings` (`min_rows_for_chunked_h5_copy` default, validation and the row slices read when copying a dense X)
- Each case has `result`, `error`, `warnings`, `state_after` (`isbacked`, `filename`, `file_is_open`, `file_mode`), `original_exists`, `original_changed` and `original_after` (what `read_h5ad()` makes of the file, only when its bytes changed)
- Strings are written as `string-array` (`allow_write_nullable_strings = False`), because `read_elem_partial()` has no reader for `nullable-string-array`
- Quirks later tickets must match or decide on:
  - Assigning X on a backed object never touches the file or warns, and makes the object not backed (`isbacked` FALSE, `filename` kept), after which `write()` and `filename<-` raise "Provide a filename!"
  - With `raw`, `write()`, `write(same path)`, `copy(same path)` and `filename<-` new path fail with `AttributeError: Could not find dataset for raw X` and leave the file without `raw`
  - `write()` works in `"r"` mode (it reopens with `"a"`), and `view$write()` on the backing file corrupts it (obs subset, X whole)
  - `filename<-` NULL on a backed object with raw loses `raw$X`, and in-memory `filename<-` writes X dense
  - Sparse handle indexing bugs: negative and out-of-range indices (`X[-1]`, `X[-3:]`, `X[10]`, `X[::-1]` drops row 0) give wrong values or odd errors
  - Dense handles reject unsorted and duplicate indices, and only allow one index vector
  - `read_elem_partial` takes `(rows, cols)` for dataframes and a 1-tuple for categoricals, and has no reader for dict, scalars or nullable strings
  - `chunk_X(select = integer)` is random (the table seeds `np.random`)
- The spec line "operations that need writing raise Python's error in `"r"` mode" holds for `file[k] = v`, in-place dense `X[0, 0] <- v` and sparse `append`, not for `X<-`
