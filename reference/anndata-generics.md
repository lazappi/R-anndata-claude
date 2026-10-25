# Base R generics for AnnData

[`dim()`](https://rdrr.io/r/base/dim.html) is `c(n_obs, n_vars)`,
[`dimnames()`](https://rdrr.io/r/base/dimnames.html) is
`list(obs_names, var_names)` and
[`length()`](https://rdrr.io/r/base/length.html) is `n_obs`, like
Python's `len()`. [`nrow()`](https://rdrr.io/r/base/nrow.html) and
[`ncol()`](https://rdrr.io/r/base/nrow.html) follow from
[`dim()`](https://rdrr.io/r/base/dim.html). Comparison operators (`==`,
`!=`, `<` and so on) are not supported and raise an
`anndata_not_implemented_error`, as Python's `__eq__` raises
`NotImplementedError`, so compare the desired attributes instead.

## Usage

``` r
# S3 method for class 'AnnData'
dim(x)

# S3 method for class 'AnnData'
dimnames(x)

# S3 method for class 'AnnData'
length(x)

# S3 method for class 'AnnData'
Ops(e1, e2)
```

## Arguments

- x:

  An
  [`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
  object.

- e1, e2:

  Operands of a comparison.

## Value

[`dim()`](https://rdrr.io/r/base/dim.html) an integer vector of length
2, [`dimnames()`](https://rdrr.io/r/base/dimnames.html) a list of two
character vectors and [`length()`](https://rdrr.io/r/base/length.html) a
single integer.

## Examples

``` r
adata <- AnnData(matrix(as.numeric(1:6), nrow = 3))
dim(adata)
#> [1] 3 2
dimnames(adata)
#> [[1]]
#> [1] "0" "1" "2"
#> 
#> [[2]]
#> [1] "0" "1"
#> 
length(adata)
#> [1] 3
```
