# Matrix value helpers

Internal helpers for the array values held in X, layers, obsm, varm,
obsp and varp. Accepted values are base `matrix` or `array` (double,
integer or logical), `dgCMatrix`/`lgCMatrix` (CSC) and
`dgRMatrix`/`lgRMatrix` (CSR). Other `Matrix` classes are coerced,
sparse to CSC and dense to base `matrix`.

## Usage

``` r
as_anndata_matrix(
  x,
  allow_array = FALSE,
  what = "value",
  call = rlang::caller_env()
)

matrix_dim(x)

matrix_subset(x, i = NULL, j = NULL)

matrix_transpose(x)
```

## Arguments

- x:

  A matrix-like value.

- allow_array:

  Whether arrays with more than 2 dimensions are accepted.

- what:

  Description of the value used in error messages.

- call:

  The call reported by errors.

- i, j:

  Integer positions (1-based) on the first and second dimension, or
  `NULL` to keep that dimension whole.

## Details

The On-disk dtype record is the `anndata_dtype` attribute. The helpers
copy it onto every result that keeps the values.
