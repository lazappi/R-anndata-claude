# read_h5ad and write_h5ad options

Status: needs-triage
Type: task
Blocked by: 10

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
