# Index helpers

Internal helpers that turn an R index into positions along one axis.
Indices use R semantics, a deliberate deviation from Python: positive
integers are 1-based positions (repeats and reordering allowed),
negative integers exclude positions, logical vectors must have the
length of the axis and character vectors match names, taking the first
match. Zero, `NA`, unknown names, out-of-range positions and mixed signs
raise an `anndata_index_error`.

## Usage

``` r
normalize_index(i, names, what, call = rlang::caller_env())

subset_frame(df, idx = NULL)
```

## Arguments

- i:

  An index, or `NULL` to keep the whole axis.

- names:

  The names along the axis.

- what:

  Description of the axis used in error messages.

- call:

  The call reported by errors.

- df:

  A `DataFrame` or `data.frame`.

- idx:

  Integer positions, or `NULL` to keep every row.

## Deviations from Python

The indices above. See
[`vignette("deviations")`](https://lazappi.github.io/R-anndata-claude/articles/deviations.md)
for the full list.
