# Dicts

Reads and writes the Element `dict`, version 0.1.0. A `dict` is a group
whose members are Elements, and its R value is a named list.

## Usage

``` r
write_mapping(store, key, value, dataset_kwargs, path)
```

## Arguments

- store:

  An open rhdf5 file or group handle.

- key:

  Name of the Element within `store`.

- value:

  A named list.

- dataset_kwargs:

  A list of dataset creation options.

- path:

  Path of the Element.

## Details

Nested lists, empty lists and `NULL` values (written as the `null`
Element) are supported. A list that is not fully named, or that has
duplicated names, cannot be written and raises
`anndata_io_registry_error`, as does any list with a class. An empty
list is written as an empty `dict`, and an empty `dict` is read as a
named list of length 0. Members are read in the order the file lists
them, which is alphabetical for files written by h5py.
