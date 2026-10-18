# Dense lazy seeds

Status: ready-for-agent
Type: task
Blocked by: 02, 03

## What

A DelayedArray seed for dense arrays on h5ad and zarr (v3 and v2), using the store layer's selection reads, with On-disk dtype records, the 64-bit policy and Python's default chunking.

## Acceptance criteria

- Realised values equal `read_h5ad()`/`read_zarr()` for every dense fixture, and block reads read only their blocks
- `scripts/check.sh` passes

## Decisions (orchestrator, 2026-10-18)

- Accept the recommended answer for `array_int32_min` (spec "Behaviour"): keep the error, make its message suggest an eager read, document the deviation in the help page, then close this ticket (version bump and tag).

## Comments

2026-10-18: Implemented `StoreDenseSeed` (`R/lazy-dense.R`, tests in `test-lazy-dense.R`): a DelayedArray seed over `array_read()` for h5ad, zarr v3 and v2, with `type()` fixed from the dtype, `chunkdim()` following `resolve_chunks()` (`chunks` argument with `NA`/`-1` for the whole axis, on-disk chunks, else `min(1000, axis)`), `store_dense_values()` giving the values with the On-disk dtype record, and DelayedArray and S4Arrays added to Imports.
Realised values (and dtype records) equal `read_elem()` for every dense fixture on all three formats except one, and blocks read only the sorted unique positions they need (mocked `array_read`).
The 2^53 error is not tested on a fixture, as none of the dense fixtures holds such values (the read path is the shared one).

Open question for the human: `array_int32_min` (an int32 array holding -2^31, the bit pattern of `NA_integer_`).
`read_h5ad()` returns a double with an `int32` record for it, but a seed's `type()` is fixed before any read, so it cannot switch to double.
The seed raises `anndata_dtype_overflow_error` when a block holds -2^31, and the test asserts that error for this one fixture.
Recommended answer: accept it as a documented deviation (the value is in practice `NA` in R), and mark this ticket done.
The alternative, typing every int32 seed as double, would make all int32 data lazily double.
Tickets 05 and 06 are blocked by this one.
