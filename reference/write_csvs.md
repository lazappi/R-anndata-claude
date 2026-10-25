# Write annotations and uns to csv files

Writes `obs`, `var`, `obsm`, `varm` and `uns` (and X when `skip_data` is
`FALSE`) to csv files in a directory, as Python's `write_csvs()` does.
`obs.csv` and `var.csv` have a header and their names as the first
column, `obsm.csv` and `varm.csv` have one column per column of each
matrix (named by the key and the 1-based column number) and no names,
and `X.csv` and `uns/<key>.csv` have neither header nor names. Numbers
are written as pandas does, so reading the files with pandas gives the
same values whichever language wrote them.

## Usage

``` r
write_csvs(adata, dirname, skip_data = TRUE, sep = ",")
```

## Arguments

- adata:

  An
  [`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
  object.

- dirname:

  Directory to write to, created if needed. A `.csv` suffix is removed.

- skip_data:

  Whether to leave out X.

- sep:

  The field separator.

## Value

`NULL`, invisibly.

## Details

Sparse `uns` values are omitted with one `anndata_write_warning`, and so
is any `uns` value with more than 2 dimensions. A named list in `uns` (a
dict) is written as one cell holding Python's `repr` of the dict, which
supports strings, scalars and nested dicts. A View is written as its
subset and stays a View.

## Examples

``` r
adata <- AnnData(X = matrix(c(1, 2, 3, 4), 2, 2))
dir <- tempfile("csvs")
write_csvs(adata, dir, skip_data = FALSE)
list.files(dir, recursive = TRUE)
#> [1] "X.csv"    "obs.csv"  "obsm.csv" "var.csv"  "varm.csv"
unlink(dir, recursive = TRUE)
```
