# HDF5 backend of the store layer (tables)

The `table_read` and `table_write` operations of
[io-store](https://lazappi.github.io/R-anndata-claude/reference/io-store.md)
for HDF5, which hold the `rec-array` Element as a compound dataset.
rhdf5 cannot see or build the members of a compound type, so the field
types come from the compiled helper (ADR 0008, `R/io-compound.R`).

## Arguments

- store:

  An open rhdf5 file or group handle.

- key, path:

  Name or path of the dataset.

- frame:

  A `data.frame` of numeric, logical and character columns.

- values:

  The `data.frame` rhdf5 read.

- column, name:

  A column of `frame` and its name.

- dataset_kwargs:

  A list of dataset creation options.

- call:

  The call reported by errors.

## Details

Reading with `records = TRUE` records the dtype of each column that is
not the R type, as for plain arrays: the numeric name (`"uint8"`,
`"float32"`, ...) and for strings `"h5_fixed_ascii:<bytes>"` or
`"h5_fixed_utf8:<bytes>"` for a fixed-length string and
`"h5_vlen_ascii"` for an ASCII variable-length one. Variable-length
UTF-8 is what h5py writes for text, so it has no record. Writing
restores the records, and gives fields without one int32, float64, bool
and variable-length UTF-8 as h5py does. A string record is overridden
when the text does not fit (a fixed width is widened). Fixed-length
UTF-8 records and non-ASCII text in a fixed-length field are written as
variable-length UTF-8, because anndata fails to read either. Records of
zarr are ignored.
