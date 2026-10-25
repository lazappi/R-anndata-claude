# zarr backend of the store layer (reading)

The read operations of
[io-store](https://lazappi.github.io/R-anndata-claude/reference/io-store.md)
for a local zarr directory store, version 2 or 3, sharded or not,
consolidated or not, through Rarr. The write operations are in
[io-store-zarr-write](https://lazappi.github.io/R-anndata-claude/reference/io-store-zarr-write.md).

## Usage

``` r
zarr_open(path, call = rlang::caller_env())
```

## Arguments

- path:

  Path of the store directory.

- call:

  The call reported by errors.

## Details

A handle is a `zarr_node`: the store directory, the absolute path of the
node within the store and the zarr format. Metadata is always read from
the node's own files, so consolidated metadata is neither needed nor
trusted. Rarr cannot read complex values, and turns 64-bit integers (and
uint32) beyond the R integer range into `NA`. Those arrays are read
again as 32-bit integers or float64 from a temporary copy of the array
with a trailing dimension, which holds the same bytes, and the values
are put together in R.
