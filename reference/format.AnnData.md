# Format and print an AnnData object

Reproduces Python's `repr`: the shape followed by the keys of each
non-empty Slot. X is listed in `layers` as `None (.X)`.

## Usage

``` r
# S3 method for class 'AnnData'
format(x, ...)

# S3 method for class 'AnnData'
print(x, ...)
```

## Arguments

- x:

  An
  [`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
  object.

- ...:

  Ignored.

## Value

[`format()`](https://rdrr.io/r/base/format.html) returns a single
string, [`print()`](https://rdrr.io/r/base/print.html) returns `x`
invisibly.

## Examples

``` r
adata <- AnnData(matrix(0, 2, 3))
print(adata)
#> AnnData object with n_obs × n_vars = 2 × 3
#>     layers: None (.X)
```
