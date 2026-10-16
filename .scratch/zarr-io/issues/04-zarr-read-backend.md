# Reading zarr stores

Status: done
Type: task
Blocked by: 02, 03

## What

The zarr backend for reading, through Rarr (ADR 0007).

- Open a directory store, v2 or v3, consolidated or not, and walk groups, arrays and attributes
- Read arrays of every dtype, strings, scalars (shape from metadata) and sharded v3 arrays
- Apply the On-disk dtype records and the 64-bit integer policy exactly as for h5ad
- A `.zip` path raises a classed error suggesting unzipping it
- Unit tests read the zarr fixtures at this level, before any encoding

## Acceptance criteria

- Every array in the v3 and v2 fixtures reads with the right values, shape and On-disk dtype record
- `scripts/check.sh` passes

## Comments

2026-10-16: done.

- `R/io-store-zarr.R` is `zarr_backend()`, the read operations of the store layer for a local directory store (v2 or v3).
  A handle is a `zarr_node` (store directory, absolute path, format) and `zarr_open(path)` makes the root, `store_backend()` dispatches on it.
  `table_read`, the write operations and `null_write` are absent (tickets 05 and 07)
- Metadata is read from each node's own `zarr.json`, `.zarray`, `.zgroup` and `.zattrs`, so consolidated metadata is never needed (and never trusted, so a stale `.zmetadata` cannot mislead).
  Using it as a speed-up is left out because whole-array reads do not need it
- The shape comes from the metadata (Rarr returns a 1-element array for 0-d), and 0-d and 1-d arrays have no `dim`, as for HDF5
- Rarr turns 64-bit values beyond the R integer range (and uint32 above 2^31) into `NA` with a warning, and cannot read complex at all.
  `zarr_split_read()` handles both by copying the array's chunk files to a temporary store whose metadata has a trailing dimension (uint16 parts, or float64 pairs for complex128) and a chunk key that gains a trailing `0`.
  The bytes are unchanged, so the values are put together in R. Sharded arrays work the same way.
  The fallback is only used when Rarr warns, and complex128 always uses it.
  Non-zero fill values, big-endian data and the `transpose` codec raise `anndata_not_supported_error` on that path
- 64-bit and uint32 values are doubles (as for HDF5) and values of magnitude 2^53 or more raise `anndata_dtype_overflow_error`.
  An int32 `-2^31` reads as double with an `int32` record, and complex64 raises `anndata_dtype_error`
- Tests read every `array_*`, `scalar_*` and `string_array_*` fixture in every variant and compare with the h5ad fixture of the same case read through the HDF5 backend, and build big 64-bit and complex stores by hand (the fixtures hold no such values)
- `jsonlite` moved from Suggests to Imports, the `read_zarr_array` placeholder import is gone, and `zarr_fixture_manifest()` moved to `helper-python.R`
- Not done here, as planned: rec-array (`struct`) arrays go through `table_read` in zarr-io/07
