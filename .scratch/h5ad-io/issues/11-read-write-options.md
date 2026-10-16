# read_h5ad and write_h5ad options

Status: done
Type: task
Blocked by: 10, core-object/14

## What

Add the remaining arguments and conditions from "Public functions" in the spec.

- `compression` (`"gzip"`, `"lzf"`) and `compression_opts`
- `as_dense` with Python's errors, `as_sparse`, `as_sparse_fmt` and `chunk_size`
- `convert_strings_to_categoricals` modifying the object in place, including `raw$var`
- X and layers with more than 2 dimensions: error on write, warning on read
- Every other error and warning in `write_h5ad()` and `read_h5ad()`

## Acceptance criteria

- Each option and each error and warning is tested by class, confirmed against Python
- Compressed files are read by Python and the compression is visible in the file structure
- `scripts/check.sh` passes

## Comments

2026-10-16: Added `compression`, `compression_opts`, `as_dense` to `write_h5ad()` and `as_sparse`, `as_sparse_fmt`, `chunk_size` to `read_h5ad()`.
- `dataset_kwargs` (`R/io-compression.R`) reaches every dataset writer, chunks are a port of h5py's `guess_chunk()`, and scalars and `null` are never compressed. `as_dense` travels as an internal `dataset_kwargs` key.
- Deviations from Python, all deliberate: invalid values are classed errors raised before the file is opened, `chunk_size` 0 or negative is an error (Python hangs), `as_sparse` on an X already sparse is `anndata_invalid_argument_error` (Python gives an `AttributeError`), and `/raw` keeps its Encoding attributes when raw X is written dense (Python drops them).
- `read_h5ad(as_sparse=)` reads the dense dataset whole and converts it in chunks, so it does not lower peak memory.
- rec-arrays are still uncompressed (h5ad-io/15).
- rhdf5 gotchas: `H5Pset_lzf()` segfaults on a variable-length string type (a 16-byte type stands in), `H5Tget_size()` gives `NULL` for it, and `H5Pset/get_chunk` use HDF5 (row-major) order.
