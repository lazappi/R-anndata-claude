# Backed mode

Status: ready-for-agent

Sub-project 7 of the roadmap (`.scratch/roadmap/spec.md`), after `views`.
`read_h5ad(file, backed = "r"/"r+")` returns an `AnnData` whose X stays on disk, matching Python's backed mode.

Python references are relative to `.reference/anndata/src/anndata/`: `_core/file_backing.py` (`AnnDataFileManager`, `to_memory`), `_core/sparse_dataset.py` (`sparse_dataset` `:593`, `BaseCompressedSparseDataset`), `_io/h5ad.py:184-213` (`read_h5ad_backed`), `_core/anndata.py` (`isbacked`/`filename` `:1002-1060`, `to_memory` `:1397`, `chunked_X`/`chunk_X` `:1832-1898`, the X getter `:595-615`), `_io/specs/registry.py:550` (`read_elem_partial`) and `_io/specs/methods.py:533` (`min_rows_for_chunked_h5_copy`).

## Decisions (human, 2026-10-17)

- Backed X is our own small classes, one dense and one sparse, supporting `dim()`, `[` (reading the selection into memory) and conversion to in-memory matrices, which is what Python's handles support.
  They are designed so that `lazy` can wrap them as DelayedArray seeds later, and DelayedArray itself is decided in `lazy`.
- `adata$file` mirrors Python's file manager: `open()`, `close()`, `is_open` and `filename`.
  Reading X after a close reopens the file as Python does, an R6 finalizer closes it on garbage collection, `backed = "r"` opens read-only (`H5F_ACC_RDONLY`) and `"r+"` read-write.
- h5ad only, as in Python (the store layer's selections would allow zarr later)
- Expected behaviour comes from a Python-generated operations table, as for views

## Scope

In:

- `read_h5ad(backed = "r" | "r+" | TRUE)`, `adata$isbacked`, `adata$filename` (getter and setter), `adata$file`, and the ` backed at '<file>'` suffix in `print()`/`format()`
- Backed dense X and backed sparse X (CSR and CSC), and `raw$X`, which stay on disk while every other Slot is read into memory (`read_h5ad_backed`)
- `sparse_dataset()`, exported as Python's `anndata.io.sparse_dataset()` is
- Views of backed objects, which read only their subset
- Assigning X in `"r+"` mode, `write()` and `write_h5ad()` on a backed object, `copy(filename)`, `to_memory(copy = FALSE)`, and moving into and out of backed mode by setting `filename`
- `chunked_X(chunk_size)` and `chunk_X(select, replace)`, which apply to in-memory objects too
- `read_elem_partial()` and the setting `min_rows_for_chunked_h5_copy`
- The deferred rows of the Views operations table for `to_memory`, `chunked_X` and `chunk_X`

Out:

- zarr backed mode (not in Python)
- Lazy reading and DelayedArray (`lazy`)

## Behaviour

- Every operation, error and warning follows Python, as recorded in the operations table
- Indexing backed X accepts the R index forms of the core-object spec and returns ordinary in-memory values (a matrix, or a sparse matrix in the same format)
- Reading a sparse selection reads only the needed parts of `data` and `indices` (caching `indptr` as Python does is an implementation choice)
- On-disk dtype records apply to values read from backed X, as for `read_h5ad()`
- A closed file is reopened on access, and operations that need writing raise Python's error in `"r"` mode
- Writing a backed object never loads the whole X into memory at once when Python does not (`min_rows_for_chunked_h5_copy`)

## Expected behaviour table

`tests/python/backed_cases.py` (registered in `scripts/regenerate-fixtures.sh`) writes a JSON table to `tests/testthat/fixtures/`.
For each operation on a backed object, in `"r"` and `"r+"` modes and for dense and sparse X, it records the result, any error or warning (class and message) and the file's state afterwards.
Operations cover at least: reading and slicing X, Views of backed objects, assigning X, `to_memory()`, `copy()` and `copy(filename)`, `write()`, setting `filename` (to a new file, to the same file and to `NULL`), `chunked_X()`, `chunk_X()`, closing then reading, `print()`, and `read_elem_partial()`.

## Required tests

- Every row of the operations table
- Every R index form on backed dense and sparse X, compared with the same selection of the in-memory matrix
- Files written from backed objects are Structurally equivalent to Python's results for the same operations
- The file handle is closed after garbage collection and after `close()`

## Acceptance criteria

- Every row of the backed operations table and the deferred Views rows pass
- `scripts/check.sh` passes
