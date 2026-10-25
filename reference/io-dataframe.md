# Data frames

Reads and writes the Element `dataframe`, version 0.2.0, a group with
the attributes `_index` and `column-order`, one member per column and
one for the index. Its R values are
[`S4Vectors::DataFrame`](https://rdrr.io/pkg/S4Vectors/man/DataFrame-class.html)
(read and written) and `data.frame` (written).

## Usage

``` r
write_dataframe(store, key, value, dataset_kwargs, path)
```

## Arguments

- store:

  An open rhdf5 file or group handle.

- key:

  Name of the Element within `store`, `"/"` writes into the root.

- value:

  The R value to write.

- dataset_kwargs:

  A list of dataset creation options.

- path:

  Path of the Element within `store`.

## Details

The index is the row names, with the index name in `metadata()` under
`index_name` (the `index_name` attribute of a `data.frame`). The member
is called `_index` when there is no index name. Row names that are
`NULL` (or automatic for a `data.frame`) are written as Python writes a
`RangeIndex`, an int64 `array` of `0` to `n - 1`. An index that is not a
plain string vector (integer, categorical or a string-array) is kept in
`metadata()` under `index_source` and written back as it was, as long as
the row names still match it.

Columns follow the rules of the Elements they are written as. A
`character` column is a `nullable-string-array` as pandas 3 writes a
`str` column, unless it was read from a plain `string-array` or the
setting `allow_write_nullable_strings` is `FALSE` (see
[io-nullable](https://lazappi.github.io/R-anndata-claude/reference/io-nullable.md)).
A column must be a vector without a `dim` of more than one dimension,
and column names must be unique and not `_index`.
