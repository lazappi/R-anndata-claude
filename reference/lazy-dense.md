# Dense lazy seeds

A `StoreDenseSeed` is a DelayedArray seed for a dense Element on disk,
in h5ad or zarr (v3 and v2). It holds an open store handle and the path
of the array and reads blocks with the store layer's selection reads
([`array_read()`](https://lazappi.github.io/R-anndata-claude/reference/io-store.md)),
so one code path serves every format. The seed has the shape of the
array in Python's order, which is the order of the R array, so no
transposing is needed.

## Usage

``` r
store_dense_seed(
  store,
  path,
  chunks = NULL,
  call = rlang::caller_env(),
  strings = FALSE
)

# S4 method for class 'StoreDenseSeed'
dim(x)

# S4 method for class 'StoreDenseSeed'
dimnames(x)

# S4 method for class 'StoreDenseSeed'
extract_array(x, index)

store_dense_values(x)
```

## Arguments

- store:

  An open store handle, see
  [io-store](https://lazappi.github.io/R-anndata-claude/reference/io-store.md).

- path:

  Absolute path of the dense array.

- chunks:

  Optional chunk shape, one entry per dimension.

- call:

  The call reported by errors.

- strings:

  Whether a string array is accepted (type `character`, used for string
  columns of lazy data frames).

- x:

  A `StoreDenseSeed`.

- index:

  A list with one entry per dimension, `NULL` (every index) or a vector
  of positions.

## Details

Its `type()` is fixed from the On-disk dtype and not from a read,
because a small h5ad selection of int64, uint32 or uint64 comes back as
`integer` where a whole read gives `double`. The types are those of
[`read_h5ad()`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md):
`integer` for int8, int16, int32, uint8 and uint16, `logical` for bool
and `double` otherwise. Blocks are plain arrays, so use
`store_dense_values()` to get the values with the On-disk dtype record
that
[`read_h5ad()`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md)
gives. Reading int64 or uint64 values of magnitude 2^53 or more raises
the error of
[`read_h5ad()`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md)
when the block holding them is realised.

`chunkdim()` is the chunk grid of Python's
[`read_elem_lazy()`](https://lazappi.github.io/R-anndata-claude/reference/read_elem_lazy.md):
the `chunks` argument if given (`NA` or `-1` for the whole axis),
otherwise the on-disk chunk shape (the inner chunk shape of sharded
zarr), and for a contiguous HDF5 dataset 1000 or the axis length when
that is smaller. The handle must stay open while the seed is used.

## Deviations from Python

An int32 array holding -2^31 (the bit pattern of `NA_integer_`) is read
as `double` by
[`read_h5ad()`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md),
but a seed's type is fixed before any read. Realising a block that holds
-2^31 therefore raises `anndata_dtype_overflow_error`, suggesting an
eager read. See
[`vignette("deviations")`](https://lazappi.github.io/R-anndata-claude/articles/deviations.md)
for the full list.
