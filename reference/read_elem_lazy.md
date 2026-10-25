# Read an Element lazily

`read_elem_lazy()` reads the metadata of an Element and leaves its data
on disk, so values are read only when they are realised or processed by
block. It matches Python's `read_elem_lazy()`.

## Usage

``` r
read_elem_lazy(store, path = "/", chunks = NULL)
```

## Arguments

- store:

  An h5ad file or a zarr directory (v3 or v2), given as a path or as an
  open store handle.

- path:

  Path of the Element within the store.

- chunks:

  Chunk shape of the `DelayedArray` grid, one entry per dimension, where
  `NA` or `-1` is the whole axis. The default is the on-disk chunking
  (1000 where an HDF5 array is contiguous) and for sparse arrays the
  major axis is cut every 1000 positions. Sparse arrays can only be
  chunked along the major axis. Ignored for string, categorical,
  nullable and `dataframe` Elements.

## Value

A `DelayedArray`, or a lazy column or data frame.

## Details

**\[experimental\]**

What is returned depends on the encoding of the Element:

- dense and sparse (CSR and CSC) arrays are `DelayedArray`s, sparse ones
  stay sparse (SparseArray) when processed by block

- string arrays are 1-d `DelayedArray`s of `character`

- categorical and nullable arrays are lazy columns, and a `dataframe` is
  a lazy data frame whose columns are lazy

- other encodings (such as `dict` and scalars) raise
  `anndata_io_registry_error`, as in Python

Realising a lazy value gives what
[`read_h5ad()`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md)
and
[`read_zarr()`](https://lazappi.github.io/R-anndata-claude/reference/zarr.md)
give for the same Element, including `NA` and the On-disk dtype records.
The store stays open while any lazy object that uses it exists.

## Deviations from Python

`store` is a path or an open store handle, because R has no element
object like h5py's. See
[`vignette("deviations")`](https://lazappi.github.io/R-anndata-claude/articles/deviations.md)
for the full list.

## Examples

``` r
adata <- AnnData(matrix(as.numeric(1:6), nrow = 3))
path <- tempfile(fileext = ".zarr")
write_zarr(adata, path)
read_elem_lazy(path, "X")
#> <3 x 2> DelayedMatrix object of type "double":
#>      [,1] [,2]
#> [1,]    1    4
#> [2,]    2    5
#> [3,]    3    6
```
