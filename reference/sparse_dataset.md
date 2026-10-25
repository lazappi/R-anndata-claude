# Handle on a sparse matrix on disk

Makes a handle on a `csr_matrix` or `csc_matrix` Element that is open in
an rhdf5 group, as Python's `anndata.io.sparse_dataset()` does. The
handle reads only the parts of `data` and `indices` that an index needs
(see `[`, [`as.matrix()`](https://rdrr.io/r/base/matrix.html) and
`$to_memory()`), and it is also what a backed object holds as `X`. It
reads from the group while the group stays open, and the caller closes
the group. `handle$append(value)` adds the rows (CSR) or columns (CSC)
of a sparse matrix in the same format to the file, which must be open
read-write and hold resizable `data`, `indices` and `indptr` (as files
written by Python do), and the handle's shape grows with it.

## Usage

``` r
sparse_dataset(group, ..., should_cache_indptr = TRUE)
```

## Arguments

- group:

  An open rhdf5 group handle holding a `csr_matrix` or `csc_matrix`
  Element.

- ...:

  Must be empty, because Python takes `should_cache_indptr` by name
  only.

- should_cache_indptr:

  Whether to read `indptr` once and keep it.

## Value

A `backed_sparse`, which has the fields `shape`, `dtype`, `format`
(`"csr"` or `"csc"`) and `backend` (`"hdf5"`).

## Examples

``` r
path <- tempfile(fileext = ".h5ad")
x <- Matrix::sparseMatrix(i = c(1, 3), j = c(2, 3), x = c(5, 6))
write_h5ad(AnnData(methods::as(x, "RsparseMatrix")), path)
file <- rhdf5::H5Fopen(path, flags = "H5F_ACC_RDONLY")
group <- rhdf5::H5Gopen(file, "X")
handle <- sparse_dataset(group)
handle$format
#> [1] "csr"
handle[3, ]
#> [1] 0 0 6
rhdf5::H5Gclose(group)
rhdf5::H5Fclose(file)
```
