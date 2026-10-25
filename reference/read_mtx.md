# Read a Matrix Market file

`read_mtx()` reads a `.mtx` file (Matrix Market, coordinate or array
format, with the `integer`, `real` or `pattern` field) into an
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
object with a CSR X, as Python's `read_mtx()`. The `obs` and `var` names
are `"0"`, `"1"` and so on. Symmetric and skew-symmetric matrices are
expanded to the full matrix.

## Usage

``` r
read_mtx(filename, dtype = "float32")
```

## Arguments

- filename:

  A path (a `.gz` or `.bz2` suffix is decompressed).

- dtype:

  A numpy dtype string for X, such as `"float32"` (the default),
  `"float64"` or `"int32"`. The values are R doubles that carry the
  On-disk dtype.

## Value

An
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
object with a sparse (CSR) X.

## Examples

``` r
path <- tempfile(fileext = ".mtx")
writeLines(
  c(
    "%%MatrixMarket matrix coordinate integer general",
    "2 3 2",
    "1 1 5",
    "2 3 7"
  ),
  path
)
read_mtx(path)
#> AnnData object with n_obs × n_vars = 2 × 3
#>     layers: None (.X)
```
