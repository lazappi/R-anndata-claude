# Arrays, scalars, strings, null and bytes

Reads and writes the Elements `array`, `string-array`, `numeric-scalar`,
`string`, `null` and `bytes` (read only), all version 0.2.0 except
`null` (0.1.0).

## Usage

``` r
h5_space(dims, scalar, resizable = FALSE)

write_bool_dataset(loc, name, x, scalar, call, dataset_kwargs = list())

write_complex_dataset(loc, name, x, scalar, call, dataset_kwargs = list())

write_string_dataset(loc, name, x, scalar, call, dataset_kwargs = list())
```

## Arguments

- dims:

  Dimensions of the array as Python sees them.

- scalar:

  Whether to use a scalar dataspace.

- loc:

  An open rhdf5 file or group handle.

- name:

  Name or path of a dataset below `loc`.

- x:

  An atomic vector, matrix or array.

- call:

  The call reported by errors.

## Details

R has no scalars, so Python's rule is kept with the `dim` attribute:

- a length-1 atomic vector with no `dim` is written as a
  `numeric-scalar` or `string`

- a length-1 vector with a `dim` (or wrapped in
  [`as_array()`](https://lazappi.github.io/R-anndata-claude/reference/as_array.md))
  is written as a 1-element `array` or `string-array`

- an Element read from disk remembers its Encoding type the same way, a
  scalar has no `dim` and a 1-element array has `dim` 1

Scalars are never compressed. Arrays have
[`dim()`](https://rdrr.io/r/base/dim.html) equal to the shape Python
sees, and a `logical` array without `NA` is written as h5py's boolean.
`NA_real_` and `NaN` are both written as NaN and read as `NaN`. Only
complex128 is written, and reading complex64 raises
`anndata_dtype_error` because rhdf5 reads it incorrectly. `bytes` is
read as a `raw` vector. Integer, logical and character values with `NA`
are written as the nullable Elements, see
[io-nullable](https://lazappi.github.io/R-anndata-claude/reference/io-nullable.md).
Complex values with `NA` cannot be written and raise
`anndata_io_registry_error`.
