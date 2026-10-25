# Dataset compression

`dataset_kwargs` holds the dataset creation options that
[`write_elem()`](https://lazappi.github.io/R-anndata-claude/reference/io-registry.md)
passes down to every dataset, as h5py's keywords do. `compression` is
`"gzip"` or `"lzf"`, and `compression_opts` is the gzip level from 0 to
9 (4 when `NULL`), which `"lzf"` does not accept. A compressed dataset
is chunked with the shape h5py guesses, and scalars and the `null`
Element are never compressed, as in Python. The internal key `as_dense`
lists the Elements to write dense, see
[`write_h5ad()`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md).

## Usage

``` r
check_compression(compression, compression_opts, call = rlang::caller_env())

guess_chunk(dims, typesize)

make_dcpl(dataset_kwargs, dims, type)
```

## Arguments

- compression, compression_opts:

  As in
  [`write_h5ad()`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md).

- call:

  The call reported by errors.

- dims:

  Dimensions of the dataset as HDF5 sees them (row-major).

- typesize:

  Size of one element in bytes.

- dataset_kwargs:

  A list of dataset creation options.

- type:

  An HDF5 type name or handle.
