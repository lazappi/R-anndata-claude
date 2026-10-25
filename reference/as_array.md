# Mark a vector as an array

R has no scalars, so a length-1 vector is written to an h5ad file as a
scalar unless it has a `dim`. `as_array()` gives a vector a `dim` so
that it is written as a 1-element array, as Python writes a 1-element
`numpy` array. A value that already has a `dim` is returned unchanged.

## Usage

``` r
as_array(x)
```

## Arguments

- x:

  An atomic vector, matrix or array.

## Value

`x` with a `dim`.

## Examples

``` r
as_array(1.5)
#> [1] 1.5
```
