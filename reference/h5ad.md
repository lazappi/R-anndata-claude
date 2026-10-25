# Read and write h5ad files

`read_h5ad()` reads an `.h5ad` file into an
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md),
and `write_h5ad()` (also `adata$write_h5ad()`) writes one, following
Python anndata 0.13.4 (`h5ad.py`). Files round trip between R and
Python.

## Usage

``` r
read_h5ad(
  filename,
  backed = NULL,
  as_sparse = character(),
  as_sparse_fmt = c("csr", "csc"),
  chunk_size = 6000L
)

write_h5ad(
  adata,
  filename,
  compression = NULL,
  compression_opts = NULL,
  as_dense = character(),
  convert_strings_to_categoricals = TRUE
)
```

## Arguments

- filename:

  Path of the `.h5ad` file.

- backed:

  `NULL` or `FALSE` to read everything into memory, `"r"` or `"r+"` to
  keep `X` and `raw$X` on disk (read-only or read-write, see
  `adata$file`), and `TRUE` for `"r+"`. `as_sparse` has no effect in
  backed mode.

- as_sparse:

  Elements stored dense to read as sparse matrices, `"X"` and/or
  `"raw/X"` (`"raw.X"` is accepted too). An Element that is already
  sparse on disk is an error.

- as_sparse_fmt:

  Sparse format of `as_sparse`, `"csr"` or `"csc"`.

- chunk_size:

  Number of rows (CSR) or columns (CSC) converted to sparse at a time.

- adata:

  An
  [`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md).

- compression:

  `NULL`, `"gzip"` or `"lzf"`, the HDF5 filter applied to every dataset
  except scalars.

- compression_opts:

  The gzip level from 0 to 9 (4 when `NULL`), which `"lzf"` does not
  accept.

- as_dense:

  Sparse matrices to write dense, `"X"` and/or `"raw/X"` (`"raw.X"` is
  accepted too), which keeps the On-disk dtype. Dense matrices are
  written as they are. Unlike Python the `/raw` group keeps its Encoding
  attributes.

- convert_strings_to_categoricals:

  Whether to convert character columns to factors before writing.

## Value

`read_h5ad()` returns an
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
and `write_h5ad()` returns `NULL` invisibly.

## Details

`write_h5ad()` replaces an existing file. With
`convert_strings_to_categoricals`, character columns of `obs`, `var` and
`raw$var` with fewer distinct values than rows are converted to factors
in `adata` first, **in place**, as Python does. `X` and every layer must
have at most 2 dimensions.

`adata$unwriteable()` reports whether the object holds a value that
cannot be written, which is `TRUE` for a value without an encoding (a
function, a `Date`, a partly named list) and for `X` or a layer with
more than 2 dimensions. `store_type` is `NULL`, `"h5"` or `"zarr"` and
does not change the result, because every Element that can be written to
one store can be written to the other.

Files from old anndata releases are read too (also in backed mode), each
Element written without encoding metadata raising
`anndata_old_format_warning` (Python's `OldFormatWarning`) and writing
always uses the current encodings (see
[`read_lazy()`](https://lazappi.github.io/R-anndata-claude/reference/read_lazy.md)
for lazy reading).

## Deviations from Python

A sparse matrix whose `indices` are out of range (such as 1-based
indices) raises an error, where Python reads it into an invalid scipy
matrix. See
[`vignette("deviations")`](https://lazappi.github.io/R-anndata-claude/articles/deviations.md)
for the full list.

## Examples

``` r
adata <- AnnData(matrix(as.numeric(1:6), nrow = 3))
path <- tempfile(fileext = ".h5ad")
write_h5ad(adata, path)
read_h5ad(path)$shape
#> [1] 3 2

# Backed mode keeps X on disk
backed <- read_h5ad(path, backed = "r")
backed$isbacked
#> [1] TRUE
backed$file$close()
unlink(path)
```
