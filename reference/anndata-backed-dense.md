# Backed dense X

A `backed_dense` is a `backed_x` for a dense array on disk. `[` accepts
every R index form of a base matrix (positive, negative and logical
vectors, repeated and unsorted positions, `drop`) and reads only the
needed part of the file into memory. Python's dense handle rejects
unsorted and repeated indices, here they are read as a sorted selection
and then rearranged in memory. Values carry the On-disk dtype record, as
for
[`read_h5ad()`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md).
A vector index such as `x[i]` (or `x[]`) has no rows and columns to
select, so it reads the whole array.

## Arguments

- x:

  A `backed_dense`.

- i, j:

  Row and column indices, as for a base matrix.

- drop:

  Whether a single row or column becomes a vector.

- ...:

  Ignored.
