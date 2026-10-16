# Backend-neutral store layer

Status: done
Type: task
Blocked by: none

## What

Decide whether the element registry gains a backend-neutral store layer so that encodings serve both HDF5 and zarr (the spec leaves this to the agents, and the spike recommends one in its "Store abstraction" section), and if so build it with HDF5 as its first backend.

- Encodings stop calling rhdf5 directly
- Reading an array takes an optional selection (row and column slices), even though zarr-io only reads whole arrays, because `backed` and `lazy` will read slices from both HDF5 and zarr (rhdf5 and Rarr both support it)
- No behaviour change: every existing h5ad test passes unchanged
- If you decide against a shared layer, record why in a comment and describe how zarr encodings will reuse the existing ones

## Acceptance criteria

- h5ad behaviour, files and tests are unchanged
- The decision and the layer's shape are recorded in a ticket comment and in `CLAUDE.md`
- `scripts/check.sh` passes

## Comments

2026-10-16: Decided to build the shared layer, as the spike recommended.

- `R/io-store.R` holds backend-neutral wrappers (`node_open()`, `group_create()`, `attr_read()`, `attr_write()`, `array_info()`, `array_read(store, path, selection)`, `table_read()` and so on).
  Each calls `store_backend(store)$op(...)`, a list of operations chosen by the handle class.
  I used a list of functions instead of S3 methods because `.lintr` rejects dotted names like `x.H5IdComponent`.
  `store_backend()` is the only place that must learn about a zarr handle.
- `R/io-store-h5.R` is the HDF5 backend (`h5_backend()`), which wraps the existing code.
  The numeric, bool, complex and string readers and writers stayed in `R/dtype.R` and `R/io-values.R` as `h5_*` functions, and `read_dataset()`, `write_dataset()` and `write_*_dataset()` are now wrappers with the same names so tests are unchanged.
- No `R/io-*.R` encoding file calls rhdf5 now (only `io-h5ad.R` opens the file and `io-compression.R` builds HDF5 creation properties).
- Selections are a list with one entry per dimension in numpy order (`NULL` or strictly increasing 1-based indices).
  HDF5 hyperslabs need increasing indices, so others raise `anndata_invalid_value_error`.
  Variable-length strings and complex values crash HDF5 when read through a memory dataspace, so they are read whole and subset in R (`in_r`).
- zarr backend work: add a `zarr_backend()` list with the same operations, `array_info()` must give `dclass`, `dtype` and `rank` as `h5ls()` does, and a 0-d array needs its shape from metadata.
- The full `scripts/check.sh` passes and the reviewer passed.
