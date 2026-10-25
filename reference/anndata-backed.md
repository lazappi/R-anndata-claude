# Backed mode

Internal pieces of backed mode (`file_backing.py`, `read_h5ad_backed`).
`read_h5ad(backed = )` keeps X and `raw$X` on disk while every other
Slot is read into memory, and the backing file is held by an
`AnnDataFileManager` (`adata$file`).

## Arguments

- filename:

  Path of the backing file.

- filemode:

  `"r"` or `"r+"`.

- key:

  Name of a member of the file, such as `"X"` or `"raw/X"`.

- value:

  A value to write.

- manager:

  An `AnnDataFileManager`.

- path:

  Path of the array within the file.

- shape:

  The shape of the array, rows then columns.

- encoding:

  The Encoding type, `"array"`, `"csr_matrix"` or `"csc_matrix"`.

- dtype:

  The dtype of the stored values.

- store:

  An open rhdf5 file handle.

- call:

  The call reported by errors.

## Details

The manager remembers the file name and mode, and opens read-only for
`"r"` and read-write for `"r+"`.
[`close()`](https://rdrr.io/r/base/connections.html) closes the handle
but keeps the file name, so the object stays backed, and reading X (or
`raw$X`) opens the file again. A finalizer closes the handle when the
manager is garbage collected. Unlike Python only the modes `"r"` and
`"r+"` open, because `"w"` would truncate the backing file.

A `backed_x` stands for X or `raw$X` on disk. It records where the array
is and finds the open file through the manager, so it survives a close.
A dense array is also a `backed_dense` (`R/backed-dense.R`) and a sparse
matrix a `backed_sparse` (`R/backed-sparse.R`).
