# Read text and csv files

`read_text()` reads a delimited text file (`.txt`, `.tab`, `.data`) into
an
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
object and `read_csv()` is the same with the delimiter `","`, as in
Python's `read_text()` and `read_csv()`. Blank lines are skipped and
lines starting with `#` are comments. If the first line holds names (its
last field is not a number) they become the `var` names, otherwise the
last comment line is used or the names are `"0"`, `"1"` and so on. If a
line starts with a field that is not a number (or `first_column_names`
is `TRUE`) the first column holds the `obs` names, and double quotes
around names are removed. A first line with one name fewer than the
second line's values is read as integer names for both axes.

## Usage

``` r
read_text(
  filename,
  delimiter = NULL,
  first_column_names = NULL,
  dtype = "float32"
)

read_csv(
  filename,
  delimiter = ",",
  first_column_names = NULL,
  dtype = "float32"
)
```

## Arguments

- filename:

  A path (a `.gz` or `.bz2` suffix is decompressed), a connection, or a
  character vector of lines. A single line is passed as `I("...")`,
  because a single string is a path.

- delimiter:

  The field delimiter. With `NULL` lines are split at any run of white
  space, which differs from `" "`.

- first_column_names:

  Whether the first column stores the `obs` names, detected when `NULL`.

- dtype:

  A numpy dtype string for X, such as `"float32"` (the default),
  `"float64"` or `"int32"`. The values are R doubles or integers that
  carry the On-disk dtype.

## Value

An
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
object with a dense X.

## Examples

``` r
lines <- c("cell,g1,g2", "c1,1,2", "c2,3,4")
read_csv(lines)
#> AnnData object with n_obs × n_vars = 2 × 2
#>     layers: None (.X)
```
