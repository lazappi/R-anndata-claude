# Read a umi_tools count table

`read_umi_tools()` reads a (optionally gzipped) tab-separated condensed
count matrix from umi_tools, with the columns `gene`, `cell` and
`count`, into an
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
object with a sparse (CSR) X, as Python's `read_umi_tools()`. The `obs`
and `var` names are the sorted unique cells and genes (Python's category
order), with the index names `"cell"` and `"gene"`. Repeated cell and
gene pairs are summed and other columns are ignored.

## Usage

``` r
read_umi_tools(filename, dtype = NULL)
```

## Arguments

- filename:

  A path (a `.gz` or `.bz2` suffix is decompressed).

- dtype:

  A numpy dtype string for X, such as `"float32"`. With `NULL` the dtype
  of the counts is used (`"int64"` for whole numbers, otherwise
  `"float64"`).

## Value

An
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
object with a sparse (CSR) X.

## Examples

``` r
path <- tempfile(fileext = ".tsv")
writeLines(
  c("gene\tcell\tcount", "g2\tc2\t3", "g1\tc1\t1", "g3\tc1\t2"),
  path
)
read_umi_tools(path)
#> AnnData object with n_obs × n_vars = 2 × 3
#>     layers: None (.X)
```
