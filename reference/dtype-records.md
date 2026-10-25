# On-disk dtype records

Internal mechanism that keeps the On-disk dtype of numeric Elements that
R cannot represent natively (float32, int8, int16, the unsigned
integers, int64 and the sparse index dtypes).

## Usage

``` r
get_dtype(x)

set_dtype(x, dtype)

drop_dtype(x)

get_nullable(x)

set_nullable(x, na_value = TRUE)

check_dtype_fits(x, dtype, path, call = rlang::caller_env())

write_dtype(x, path, call = rlang::caller_env())

sparse_write_dtypes(x, path, call = rlang::caller_env())

read_dataset(loc, name, selection = NULL, call = rlang::caller_env())

write_dataset(
  loc,
  name,
  x,
  scalar = FALSE,
  dataset_kwargs = list(),
  call = rlang::caller_env()
)
```

## Arguments

- x:

  A numeric value.

- dtype:

  A dtype name from `numeric_dtypes`.

- path:

  Path of the Element, used in errors.

- call:

  The call reported by errors.

- loc:

  An open rhdf5 file or group handle.

- name:

  Name or path of a dataset below `loc`.

- selection:

  A selection of the array to read, see
  [io-store](https://lazappi.github.io/R-anndata-claude/reference/io-store.md).

- scalar:

  Whether to write a scalar dataspace.

- dataset_kwargs:

  A list of dataset creation options, see
  [io-compression](https://lazappi.github.io/R-anndata-claude/reference/io-compression.md).

## Details

The record is the `anndata_dtype` attribute (see
[anndata-matrix-values](https://lazappi.github.io/R-anndata-claude/reference/anndata-matrix-values.md)).
Dense values hold a single dtype name such as `"float32"`. Sparse
matrices hold a named character vector with the names `data`, `indices`
and `indptr`. Plain vectors and arrays that carry a record also get the
S3 class `anndata_typed`, whose print method hides the attribute, so
they print and compute like ordinary R values. Subsetting, copy and
transpose copy the record with `copy_dtype()`.

The nullable record is the `anndata_nullable` attribute, set by the
readers of `nullable-integer`, `nullable-boolean` and
`nullable-string-array`. It makes the value write back as a nullable
Element even when it holds no `NA`, as Python writes any pandas nullable
array. For strings it holds the `na-value` attribute (`"NaN"` or
`"NA"`), and it is `TRUE` for the other types.

Reading with `read_dataset()` records the dtype only where it differs
from the R type returned, which is `float64` for double and `int32` for
integer. Writing with `write_dataset()` restores the recorded dtype, or
the R type when there is no record, and raises
`anndata_dtype_overflow_error` when the values no longer fit. It never
truncates or wraps.

int64 and uint64 are read as double when every value has magnitude below
2^53 and otherwise raise `anndata_dtype_overflow_error`. An int32
dataset holding -2147483648, the bit pattern of `NA_integer_`, is read
as double with an `int32` record.
