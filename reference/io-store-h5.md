# HDF5 backend of the store layer

The operations of
[io-store](https://lazappi.github.io/R-anndata-claude/reference/io-store.md)
for open rhdf5 file and group handles. The dataset readers and writers
live with their encodings (`R/dtype.R`, `R/io-values.R`) as `h5_*`
functions.

## Usage

``` r
h5_dread(dset, selection = NULL, ..., in_r = FALSE)
```

## Arguments

- dset:

  An open dataset handle.

- selection:

  A selection, see
  [io-store](https://lazappi.github.io/R-anndata-claude/reference/io-store.md).

- ...:

  Further arguments of
  [`rhdf5::H5Dread()`](https://huber-group-embl.github.io/rhdf5/reference/H5Dread.html).

- in_r:

  Whether to read the whole dataset and subset it in R.
