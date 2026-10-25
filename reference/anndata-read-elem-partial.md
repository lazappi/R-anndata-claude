# Partial reads of Elements

`read_elem_partial()` reads a part of an Element, as Python's function
of the same name does. It is internal, as is
[`read_elem()`](https://lazappi.github.io/R-anndata-claude/reference/io-registry.md).
Arrays and sparse matrices read only the selected rows and columns, data
frames read the `items` (columns) and the selected rows, and
categoricals and string arrays the selected rows. Other Elements (dicts,
scalars, the root and so on) have no partial reader and raise an
`anndata_io_registry_error`. Indices follow the R rules (1-based
positions, negative and logical vectors), and the result always has the
dimensions of the selection (there is no dropping to a vector). As in
Python, a dense array, data frame or categorical needs positions in
increasing order and a sparse matrix accepts any order.

## Usage

``` r
read_elem_partial(store, path, items = NULL, rows = NULL, cols = NULL)
```

## Arguments

- store:

  An open file or group handle.

- path:

  The path of the Element in `store`.

- items:

  Names of the columns of a data frame to read, or `NULL` for all.

- rows, cols:

  R indices along the first and second dimension, or `NULL` for all.
