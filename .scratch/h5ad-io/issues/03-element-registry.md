# Element registry and error classes

Status: ready-for-agent
Type: task
Blocked by: 01, 02

## What

The dispatch layer that later tickets register encodings into.

- Read dispatch on Encoding type and Encoding version, write dispatch on R value class
- `anndata_io_registry_error` for unknown type or version (naming path, type, version) and for unencodable values (naming path and R class), covering the classes listed in the spec
- Keys containing `/` error when `disallow_forward_slash_in_h5ad` is on (`src/anndata/_io/utils.py:283`)
- Internal `read_elem()` and `write_elem()` on an open rhdf5 file or group, with `dataset_kwargs` and Python's rules for writing to `"/"` (`registry.py:424-549`), exported once at least one encoding is registered
- Classed errors for reading legacy elements (`dataframe` 0.1.0, unencoded elements, old categoricals) and `awkward-array`, naming the path and saying they are not yet supported

## Acceptance criteria

- Each error is tested by class and message content, with Python-confirmed conditions
- A trivial test encoding proves read and write dispatch
- `scripts/check.sh` passes

## Comments
