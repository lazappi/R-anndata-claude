# Sparse lazy seeds

A `StoreSparseSeed` is a DelayedArray seed for a CSR or CSC Element on
disk, in h5ad or zarr (v3 and v2). It wraps a `backed_sparse` over the
store, so it reads `indptr` once and then only the slices of `data` and
`indices` that a block needs, and the same code serves every format.
Blocks stay sparse: `extract_sparse_array()` gives an `SVT_SparseMatrix`
(SparseArray) and `is_sparse()` is `TRUE`.

## Usage

``` r
store_sparse_seed(store, path, chunks = NULL, call = rlang::caller_env())

# S4 method for class 'StoreSparseSeed'
dim(x)

# S4 method for class 'StoreSparseSeed'
dimnames(x)

# S4 method for class 'StoreSparseSeed'
extract_sparse_array(x, index)

# S4 method for class 'StoreSparseSeed'
extract_array(x, index)

store_sparse_values(x)
```

## Arguments

- store:

  An open store handle, see
  [io-store](https://lazappi.github.io/R-anndata-claude/reference/io-store.md).

- path:

  Absolute path of the sparse matrix Element.

- chunks:

  Optional chunk shape, two entries.

- call:

  The call reported by errors.

- x:

  A `StoreSparseSeed`.

- index:

  A list with one entry per dimension, `NULL` (every index) or a vector
  of positions.

## Details

As for
[lazy-dense](https://lazappi.github.io/R-anndata-claude/reference/lazy-dense.md),
`type()` is fixed from the On-disk dtype of `data` (`logical` for bool,
`integer` for int8, int16, int32, uint8 and uint16 and `double`
otherwise), and `store_sparse_values()` gives the matrix with the
On-disk dtype record that
[`read_h5ad()`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md)
gives.

`chunkdim()` follows Python's
[`read_elem_lazy()`](https://lazappi.github.io/R-anndata-claude/reference/read_elem_lazy.md)
for sparse groups: the major axis (rows for CSR, columns for CSC) is cut
every 1000 positions or every `chunks` entry (`NA` or `-1` for the whole
axis), and the minor axis is never cut, so `chunks` may only be the axis
length, `-1` or `NA` there. An axis of length 0 has a chunk of 0, as in
Python.
