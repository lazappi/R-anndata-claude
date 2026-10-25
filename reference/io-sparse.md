# Sparse matrices

Reads and writes the Elements `csr_matrix` and `csc_matrix`, both
version 0.1.0. `dgRMatrix` and `lgRMatrix` are written as `csr_matrix`,
and `dgCMatrix` and `lgCMatrix` as `csc_matrix`.

## Usage

``` r
write_shape_attr(group, shape)

write_sparse(store, key, value, dataset_kwargs, path)
```

## Arguments

- group:

  An open group handle.

- shape:

  The `shape` attribute, rows then columns.

- store:

  An open rhdf5 file or group handle.

- key:

  Name of the Element within `store`.

- value:

  A `dgRMatrix`, `lgRMatrix`, `dgCMatrix` or `lgCMatrix`.

- dataset_kwargs:

  A list of dataset creation options.

- path:

  Path of the Element.

## Details

The Element is a group holding the datasets `data`, `indices` and
`indptr` and the `shape` attribute (an int64 pair, rows then columns). A
logical matrix has boolean `data`, and a double matrix has `data` of the
dtype in its On-disk dtype record (float64 without one). `indices` and
`indptr` are int32 unless the record says otherwise, and `indices`
shrink to the smallest unsigned dtype that holds the minor axis size
when the setting `write_csr_csc_indices_with_min_possible_dtype` is on.
Reading records every dtype that differs from those defaults (see
[dtype-records](https://lazappi.github.io/R-anndata-claude/reference/dtype-records.md)).
Values that no longer fit a recorded dtype raise
`anndata_dtype_overflow_error`, and logical `NA` raises
`anndata_io_registry_error` because Python's bool has no missing value.
Complex `data` has no `Matrix` class, so it is not supported.
