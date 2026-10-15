# Element registry and error classes

Status: done
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

2026-10-15: Done (`R/io-registry.R`, `tests/testthat/test-io-registry.R`, helpers in `helper-io.R`).
- Registry is the internal env `io_registry`. Add encodings with `register_reader(type, version, fn)` (`fn(elem, path)`) and `register_writer(class, type, version, fn)` (`fn(store, key, value, dataset_kwargs, path)`). Write dispatch uses `methods::is(value)` order.
- `read_elem(store, path)` and `write_elem(store, key, value, dataset_kwargs)` are internal. Export them (with roxygen docs) in the first encoding ticket (05) once real encodings exist.
- Nested Elements must go through `write_elem()`/`read_elem_object()` so slash checks and dispatch apply at every level. Writers that write into the root (`key == "/"`) must write into `store` itself.
- Python conditions were confirmed from the 0.13.4 source (`registry.py:376-402`, `utils.py:283`), not by running Python. Errors use classes `anndata_io_registry_error`, `anndata_forward_slash_key_error`, `anndata_invalid_key_error`, `anndata_legacy_format_error` and `anndata_awkward_array_error` (the last two are also `anndata_not_supported_error`). `abort_io_registry()` and `abort_not_supported()` gained a `class` argument.
- Old-categorical detection happens in the dataframe reader, so `abort_legacy_categorical(path)` exists but is only unit tested here. Ticket 09 must call it and test it end to end.
- Not covered: Python's `report_*_key_on_error` notes (the errors name their own path instead).
