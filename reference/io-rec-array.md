# Rec-arrays

Reads and writes the Element `rec-array`, version 0.2.0, a structured
(compound) dataset such as scanpy's `rank_genes_groups` results in
`uns`.

## Usage

``` r
new_rec_array(x)

write_rec_array(store, key, value, dataset_kwargs, path)
```

## Arguments

- x:

  A `data.frame`.

- store:

  An open rhdf5 file or group handle.

- key:

  Name of the Element within `store`.

- value:

  A rec-array made by `new_rec_array()`.

- dataset_kwargs:

  A list of dataset creation options.

- path:

  Path of the Element.

## Details

The R value is a `data.frame` with the extra class `anndata_rec_array`
(made by `new_rec_array()`), which keeps the field names, field order
and field values.

Field dtypes are kept (ADR 0008, the field types come from a compiled
helper because rhdf5 cannot see or build compound types). A field read
from HDF5 or zarr carries an On-disk dtype record, unless it has the R
type, and writing restores it. Integer fields are read as `integer` (or
`double` when they do not fit) with the record `"uint8"`, `"int64"` and
so on, `f4` fields as `double` with the record `"float32"`, and booleans
as `logical`. Strings are `character`, with the record
`"h5_fixed_ascii:<bytes>"`, `"h5_fixed_utf8:<bytes>"` or
`"h5_vlen_ascii"` unless they are variable-length UTF-8 as h5py writes
text (zarr records `"<type>:<length_bytes>"`). Fields without a record
are written as int32, float64, bool and variable-length UTF-8 strings,
which Python reads with any text. A recorded string width is widened
when the text no longer fits, and a fixed-length or ASCII record becomes
variable-length UTF-8 for non-ASCII text, as does a fixed-length UTF-8
record, because anndata cannot read either as a fixed-length field.
Integer and string fields cannot hold `NA`, so writing one raises
`anndata_io_registry_error`. A rec-array with no rows is written, and
`compression = "gzip"` in `dataset_kwargs` compresses an HDF5 rec-array
(zarr uses `compressors`). Integers of 2^53 or more raise
`anndata_dtype_overflow_error` on read.

## Deviations from Python

`"lzf"` is not available to the compound helper, so an HDF5 rec-array is
written uncompressed under it. See
[`vignette("deviations")`](https://lazappi.github.io/R-anndata-claude/articles/deviations.md)
for the full list.
