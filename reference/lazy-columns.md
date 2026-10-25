# Lazy data frame columns

The columns of a lazy `obs` or `var` (see
[lazy-dataframe](https://lazappi.github.io/R-anndata-claude/reference/lazy-dataframe.md)):

- plain numeric, bool and string columns are 1-d `DelayedArray`s over a
  `StoreDenseSeed` (see
  [lazy-dense](https://lazappi.github.io/R-anndata-claude/reference/lazy-dense.md))

- a `LazyCategorical` holds a 1-d `DelayedArray` of codes and the
  categories (read at once, as they are small)

- a `LazyNullable` holds 1-d `DelayedArray`s of `values` and `mask`

## Usage

``` r
# S4 method for class 'LazyCategorical'
length(x)

# S4 method for class 'LazyNullable'
length(x)

# S4 method for class 'LazyCategorical,ANY,ANY,ANY'
x[i, j, ..., drop = TRUE]

# S4 method for class 'LazyNullable,ANY,ANY,ANY'
x[i, j, ..., drop = TRUE]

# S4 method for class 'LazyCategorical'
as.vector(x, mode = "any")

# S4 method for class 'LazyNullable'
as.vector(x, mode = "any")

# S4 method for class 'LazyCategorical'
as.data.frame(x, row.names = NULL, optional = FALSE, ...)

# S4 method for class 'LazyNullable'
as.data.frame(x, row.names = NULL, optional = FALSE, ...)

# S4 method for class 'LazyCategorical'
show(object)

# S4 method for class 'LazyNullable'
show(object)

# S4 method for class 'LazyCategorical'
showAsCell(object)

# S4 method for class 'LazyNullable'
showAsCell(object)

lazy_column(store, path, call = rlang::caller_env())
```

## Arguments

- x:

  A lazy column.

- i:

  Positions to keep.

- j, drop, ...:

  Not used.

- mode:

  Not used.

- object:

  A lazy column.

- store:

  An open store handle, see
  [io-store](https://lazappi.github.io/R-anndata-claude/reference/io-store.md).

- path:

  Absolute path of the Element of the column.

- call:

  The call reported by errors.

## Details

The two classes define [`length()`](https://rdrr.io/r/base/length.html),
`[`, `show()`, [`as.vector()`](https://rdrr.io/r/base/vector.html) and
[`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html), so they
subset, print and realise inside a `DataFrame`. `[` stays lazy and
realising gives exactly what
[`read_h5ad()`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md)/[`read_zarr()`](https://lazappi.github.io/R-anndata-claude/reference/zarr.md)
give for the same Element: the `factor` with its categories attribute,
the value with `NA` and the nullable record, the On-disk dtype record.
