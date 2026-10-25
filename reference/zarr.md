# Read and write zarr stores

`read_zarr()` reads a zarr store into an
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md),
and `write_zarr()` (also `adata$write_zarr()`) writes one, following
Python anndata 0.13.4 (`zarr.py`). Stores round trip between R and
Python.

## Usage

``` r
read_zarr(store)

write_zarr(
  adata,
  store,
  chunks = NULL,
  convert_strings_to_categoricals = TRUE,
  consolidate_metadata = TRUE,
  ...
)
```

## Arguments

- store:

  Path of the zarr directory store.

- adata:

  An
  [`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md).

- chunks:

  The chunk shape of a dense `X`, one whole number for each dimension
  (it does not apply to sparse matrices, layers or other Elements), or
  `NULL` for the default. A chunk larger than the array is cut to the
  shape of the array.

- convert_strings_to_categoricals:

  Whether to convert character columns to factors before writing.

- consolidate_metadata:

  Whether to write consolidated metadata, inline in the root
  `zarr.json`, after all Elements.

- ...:

  Dataset arguments for every array. `compressors` is `NULL` for no
  compression, a name (`"zstd"`, `"gzip"`, `"blosc"`) or a list with a
  `name` and the options of that compressor (`level` for zstd and gzip,
  `cname`, `clevel` and `shuffle` for blosc), for example
  `list(name = "gzip", level = 5)`. The default is zstd. Scalars take
  the same compressor and the `null` Element is always zstd, as in
  Python. `compressor` is accepted as Python's older name for
  `compressors`, but scalars ignore it, as in Python. `shards` is the
  shard shape, one whole number for each dimension (it applies to arrays
  of one or more dimensions, and chunks are reduced to divide it),
  `"auto"` to choose the shape, or `NULL` for no sharding. Without it,
  arrays are sharded when the `auto_shard_zarr_v3` setting is `TRUE`
  ([anndata_settings](https://lazappi.github.io/R-anndata-claude/reference/anndata_settings.md)),
  except rec-arrays which Python only shards when `shards` is given.
  Other arguments raise `anndata_invalid_argument_error`.

## Value

`read_zarr()` returns an
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
and `write_zarr()` returns `NULL` invisibly.

## Details

`read_zarr()` reads zarr version 3 stores, sharded or not, with or
without consolidated metadata, from a directory store. Version 2 is not
yet supported. Zip stores are not supported, unzip them first. Stores in
a legacy layout (such as one with `raw.X`) raise
`anndata_legacy_format_error`.

`write_zarr()` writes zarr version 3 (sharded by default) and replaces
an existing store. To protect other data it refuses a directory that is
neither empty nor a zarr group. The version is the `zarr_write_format`
setting
([anndata_settings](https://lazappi.github.io/R-anndata-claude/reference/anndata_settings.md)),
and version 2 is not yet supported. With
`convert_strings_to_categoricals`, character columns of `obs`, `var` and
`raw$var` with fewer distinct values than rows are converted to factors
in `adata` first, **in place**, as Python does. `X` and every layer must
have at most 2 dimensions. Like Python, a missing `raw` is written as a
`null` Element.

## Examples

``` r
adata <- AnnData(matrix(as.numeric(1:6), nrow = 3))
path <- tempfile(fileext = ".zarr")
write_zarr(adata, path)
read_zarr(path)$shape
#> [1] 3 2
```
