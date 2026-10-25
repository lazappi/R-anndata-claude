# Lazy data frames

A lazy `obs` or `var` is a `LazyDFrame`, an
[`S4Vectors::DataFrame`](https://rdrr.io/pkg/S4Vectors/man/DataFrame-class.html)
whose columns are lazy (see
[lazy-columns](https://lazappi.github.io/R-anndata-claude/reference/lazy-columns.md)).
Reading it reads metadata, the categories and (with
`load_annotation_index`) the index. Row subsetting, column subsetting
and printing work as for any `DataFrame` and stay lazy, and
`lazy_dataframe_realise()` gives the `DataFrame` that
[`read_h5ad()`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md)/[`read_zarr()`](https://lazappi.github.io/R-anndata-claude/reference/zarr.md)
give for the same Element.

## Usage

``` r
lazy_dataframe(
  store,
  path,
  load_annotation_index = TRUE,
  call = rlang::caller_env()
)

# S4 method for class 'LazyDFrame,ANY'
extractROWS(x, i)

# S4 method for class 'LazyDFrame'
as.data.frame(x, row.names = NULL, optional = FALSE, ...)

lazy_dataframe_realise(df, call = rlang::caller_env())
```

## Arguments

- store:

  An open store handle, see
  [io-store](https://lazappi.github.io/R-anndata-claude/reference/io-store.md).

- path:

  Absolute path of the `dataframe` Element.

- load_annotation_index:

  Whether the index is read into memory.

- call:

  The call reported by errors.

- x:

  A `LazyDFrame`.

- i:

  Row positions, already normalised by `S4Vectors`.

- df:

  A `LazyDFrame`.

## Details

With `load_annotation_index = FALSE` the row names are `NULL` (Python's
dummy range index) and the index stays a lazy column in the `lazy_index`
slot, which row subsetting follows and realising loads.
