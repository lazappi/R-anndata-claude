# zarr backend of the store layer (tables)

The `table_read` and `table_write` operations of
[io-store](https://lazappi.github.io/R-anndata-claude/reference/io-store.md)
for zarr v3, which hold the `rec-array` Element as a one-dimensional
array of the `struct` data type. Rarr cannot read or write these, so the
records are packed and unpacked in R and only the zstd and blosc steps
go through Rarr (see `zarr_compress()` and `zarr_decompress()`, gzip is
done in R).

## Arguments

- store:

  A zarr group node.

- key, path:

  Name or path of the array.

- frame:

  A `data.frame` of numeric, logical and character columns.

- call:

  The call reported by errors.

- dataset_kwargs:

  A list of dataset creation options.

- column, name:

  A column of `frame` and its name.

- values, type, size:

  Strings of a field, its data type and its width in bytes.

## Details

Python writes the fields in order, one record after another with no
padding, little-endian, with strings as `fixed_length_utf32` (zero
padded) or `null_terminated_bytes`, and compresses each chunk as
`compressors` says (zstd by default). Reading handles those codecs with
zstd, gzip, blosc or no compression, and the chunk grid of any size.
zarr keeps the field dtypes (zarr-io/14), as HDF5 does (see
[io-store-h5-table](https://lazappi.github.io/R-anndata-claude/reference/io-store-h5-table.md)),
and ignores the string records of HDF5. Reading records the dtype of
each column that is not the R type, as for plain arrays: the numeric
name (`"uint8"`, `"float32"`, ...) and for strings
`"<type>:<length_bytes>"` unless it is the `fixed_length_utf32` width
that writing would choose. Writing restores the records, and sizes
fields without one as Python does (int32, float64, bool, and
`fixed_length_utf32` of four times the longest UTF-8 byte length).
Records are one chunk, sharded only when `shards` is given because
Python's automatic sharding of rec-arrays is disabled.
