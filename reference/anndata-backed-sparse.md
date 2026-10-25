# Backed sparse X and `sparse_dataset()`

A `backed_sparse` is a `backed_x` for a CSR or CSC matrix on disk. `[`
accepts every R index form of a base matrix (positive, negative and
logical vectors, repeated and unsorted positions, `drop`) and reads only
the needed parts of `data` and `indices` into memory, using the cached
`indptr`. The result is a sparse matrix in the same format as the file
(`dgRMatrix` or `lgRMatrix` for CSR, `dgCMatrix` or `lgCMatrix` for
CSC), or a plain vector when `drop` removes a dimension, as for a
`Matrix`. Values carry the On-disk dtype record of `data`, as for
[`read_h5ad()`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md).
A vector index such as `x[i]` has no rows and columns to select, so it
reads the whole matrix. `x[]` is the whole matrix, `as.matrix(x)` its
dense form and `x$to_memory()` the sparse matrix read as
[`read_h5ad()`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md)
reads it. `x$format` is `"csr"` or `"csc"`, `x$backend` is `"hdf5"` and
`x$shape` and `x$dtype` describe the matrix.

## Arguments

- x:

  A `backed_sparse`.

- i, j:

  Row and column indices, as for a base matrix.

- drop:

  Whether a single row or column becomes a vector.

- ...:

  Ignored.

- name:

  The name of a field or method.

- rows, cols:

  Sorted, unique row and column positions.

- call:

  The call reported by errors.
