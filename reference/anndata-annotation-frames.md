# Annotation frame helpers

Internal helpers that turn user input into the
[`S4Vectors::DataFrame`](https://rdrr.io/pkg/S4Vectors/man/DataFrame-class.html)
held in obs and var (ADR 0003). Accepted input is `NULL`, a named list,
a `data.frame` or a `DataFrame`. A list may give the index in an
`obs_names`/`row_names` (or `var_names`/`col_names`) element.

## Usage

``` r
as_annotation_frame(
  anno,
  attr = c("obs", "var"),
  expected = NULL,
  source = c("X", "shape"),
  call = rlang::caller_env()
)

warn_names_not_unique(attr, call = rlang::caller_env())

check_names_unique(names, attr, call = rlang::caller_env())
```

## Arguments

- anno:

  The input value.

- attr:

  Either `"obs"` or `"var"`.

- expected:

  The number of rows required, or `NULL` to take it from the input.

- source:

  What fixed the length, `"X"` or `"shape"`, used in the error message.

- call:

  The call reported by conditions.

- names:

  Names of observations or variables.

## Details

The row names of the result are the obs_names or var_names. They are
character and may contain duplicates and `NA`. The index name is kept in
[`S4Vectors::metadata()`](https://rdrr.io/pkg/S4Vectors/man/Annotated-class.html)
under `index_name`, and is read from the same place on a `DataFrame` or
from the `index_name` attribute of a `data.frame`.
