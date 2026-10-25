# Element registry

Internal dispatch for reading and writing Elements in an open rhdf5 file
or group (`registry.py`). Reading dispatches on the Encoding type and
Encoding version stored in the `encoding-type` and `encoding-version`
attributes. Writing dispatches on the R class of the value, and records
the Encoding type and Encoding version on the written Element unless the
writer already set them.

## Usage

``` r
register_reader(type, version, fn)

register_writer(class, type, version, fn)

read_elem(store, path)

write_elem(
  store,
  key,
  value,
  dataset_kwargs = list(),
  call = rlang::caller_env()
)
```

## Arguments

- type, version:

  Encoding type and Encoding version.

- fn:

  Reader or writer function.

- class:

  R class the writer handles, matched with
  [`methods::is()`](https://rdrr.io/r/methods/is.html).

- store:

  An open rhdf5 file or group handle.

- path:

  Path of the Element within `store`.

- key:

  Name of the Element within `store`, `"/"` writes into the root.

- value:

  The R value to write.

- dataset_kwargs:

  A list of dataset creation options.

- call:

  The call reported by errors.

## Details

Encoding tickets add to the registry with `register_reader()` and
`register_writer()`. Readers are called as `fn(elem, path, store)` with
an open group or dataset handle, its absolute path and the store it was
opened from (rhdf5 cannot open a sibling dataset from a dataset handle).
Writers are called as `fn(store, key, value, dataset_kwargs, path)` with
an open group handle. Nested Elements go through `read_elem()` and
`write_elem()` so that every level is dispatched and checked.
