# Nullable arrays

Reads and writes the Elements `nullable-integer`, `nullable-boolean` and
`nullable-string-array` (all version 0.1.0), groups holding `values` and
a boolean `mask`.

## Usage

``` r
write_nullable(store, key, value, kind, dataset_kwargs, path, call)
```

## Arguments

- store:

  An open rhdf5 file or group handle.

- key:

  Name of the Element within `store`, `"/"` writes into the root.

- value:

  The R value, with its records.

- kind:

  The Encoding type to write.

- dataset_kwargs:

  A list of dataset creation options.

- path:

  Path of the Element within `store`.

- call:

  The call reported by errors.

## Details

R writes the nullable Element for the values Python writes it for:

- an `integer`, `logical` or `character` vector with `NA`

- a value read from a nullable Element, which keeps the
  `anndata_nullable` record (see
  [dtype-records](https://lazappi.github.io/R-anndata-claude/reference/dtype-records.md))
  so that it is written back as the same Element when it holds no `NA`

A plain `character` vector without `NA` is a `string-array` and a
`double` vector is never nullable, because Python has no nullable float
encoding. Integer values keep their On-disk dtype, so `nullable-integer`
of `int64` is read as `double` with an `int64` record. The `na-value`
attribute of `nullable-string-array` is `"NaN"` for new values and is
restored from the record otherwise.

With the setting `allow_write_nullable_strings` set to `FALSE`, a
`character` vector without `NA` is written as a `string-array` and one
with `NA` raises `anndata_nullable_strings_error`, as Python raises a
`ValueError`.
