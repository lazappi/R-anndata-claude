# Store layer

The backend-neutral layer between the encodings and a storage format.
Encodings (`R/io-*.R`) never call rhdf5 directly, they call the
functions here, which dispatch on the class of the handle they are given
to a backend (`store_backend()`). HDF5 (`h5_backend()`) and zarr
(`zarr_backend()`, which writes v3 only so far) each have a list of the
same operations.

## Usage

``` r
node_path(node)

elem_path(store, key)

is_store_file(store)

node_open(store, path)

node_close(node)

group_create(store, key)

is_group(node)

group_members(node)

member_exists(store, key)

member_delete(store, key)

attr_exists(node, name)

attr_write(node, name, value, dtype = NULL, scalar = TRUE)

array_info(store, path)

array_read(store, path, selection = NULL, call = rlang::caller_env())

null_write(store, key)

table_write(
  store,
  key,
  frame,
  dataset_kwargs = list(),
  call = rlang::caller_env()
)

table_read(store, path, call = rlang::caller_env(), records = FALSE)

read_elem_attr(elem, name)

set_elem_attr(elem, name, value)
```

## Arguments

- store, node:

  An open file or group handle.

- key, name:

  Name of a member of `store`, or of an attribute.

- path:

  Absolute path of an Element or array.

- value:

  The value to write.

- dtype:

  The On-disk dtype of an attribute, `NULL` for the type of `value`.

- scalar:

  Whether a character vector is written as a scalar. Character vectors
  are written as variable-length UTF-8, logicals as scalars and
  `dtype = "int64"` writes an int64 array.

- selection:

  A selection, see the description.

- call:

  The call reported by errors.

- frame:

  A data frame of numeric, logical and character columns.

- dataset_kwargs:

  A list of dataset creation options.

- records:

  Whether `table_read()` records the field dtypes (HDF5 only, zarr
  always does).

## Details

A `store` is an open file or group, and a `node` is an open group or
array. Both are handles of the backend, and paths are absolute within
the store.

A `selection` is `NULL` (the whole array) or a list with one entry per
dimension, each `NULL` (every index) or a strictly increasing vector of
1-based indices. Dimensions are in Python's order, so
`selection = list(1:2, NULL)` is numpy's `x[0:2, :]`.

The array information from `array_info()` is a one-row data frame, as
`h5ls()` gives, with `name`, `dclass` (`INTEGER`, `FLOAT`, `ENUM`,
`COMPOUND` or `STRING`), `dtype` and `rank`, and the list columns
`shape` and `chunks` (numeric vectors in Python's order). `chunks` is
`NULL` for a contiguous HDF5 dataset and for a 0-d array, and the inner
chunk shape for a sharded zarr array.
