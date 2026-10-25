# zarr backend of the store layer (writing)

The write operations of
[io-store](https://lazappi.github.io/R-anndata-claude/reference/io-store.md)
for a local zarr v3 directory store.

## Usage

``` r
zarr_create(path)

zarr_encode_values(values, dtype)

zarr_vlen_encode(values)

zarr_zstd(payload)

zarr_consolidate(path)
```

## Arguments

- path:

  Path of the store directory.

- values:

  The values of an array, in R's order.

- dtype:

  A dtype name: `numeric_dtypes`, `"bool"`, `"complex128"` or
  `"string"`.

- payload:

  A raw vector of encoded chunk bytes.

## Details

Rarr writes the chunks of numeric and bool arrays (compressed with zstd,
the codec Python uses), and the metadata (`zarr.json`) is always written
by us so that it matches what Python writes (the On-disk dtype given
explicitly, no identity `transpose` codec, the fill value and codecs of
Python). What Rarr cannot write is done here, following ADR 0007:

- 0-d arrays (scalars and `null`) and variable-length UTF-8 strings: the
  chunk bytes are encoded in R and compressed by Rarr (as a `uint8`
  array, whose single chunk is exactly the compressed bytes)

- 64-bit integers from doubles, the int32 minimum and uint32 values
  beyond the R integer range, and complex values: the bytes of each
  value are split into 16-bit (or float64) parts along a trailing
  dimension that Rarr writes, and the chunk keys then lose that
  dimension, which is the inverse of `zarr_split_read()`

The `compressors` dataset argument chooses the compressor (zstd by
default, see `zarr_compressor_arg()`), and nothing is sharded yet.
