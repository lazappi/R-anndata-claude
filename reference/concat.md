# Concatenate AnnData objects

`concat()` combines `AnnData` objects along `axis`, following Python
anndata 0.13.4 `concat()`. X and every layer present in the inputs are
stacked along `axis` and aligned on the other axis by name, either on
the names every object has (`join = "inner"`) or on all names
(`join = "outer"`).

## Usage

``` r
concat(
  adatas,
  axis = c("obs", "var"),
  join = c("inner", "outer"),
  merge = NULL,
  uns_merge = NULL,
  label = NULL,
  keys = NULL,
  index_unique = NULL,
  fill_value = NULL,
  pairwise = FALSE
)
```

## Arguments

- adatas:

  A list of `AnnData` objects. A named list uses its names as `keys`.

- axis:

  Which axis to concatenate along, `"obs"` or `"var"`.

- join:

  How to align the other axis, `"inner"` (the default) or `"outer"`.

- merge:

  How the annotation of the other axis is selected, see the Merge
  strategies section.

- uns_merge:

  How `uns` is selected, with the same strategies as `merge`.

- label:

  A column of the concatenated axis annotation that gets the `keys` of
  the objects as a factor, or `NULL` for none.

- keys:

  A name for each object (unique), by default `"0"`, `"1"`, ...

- index_unique:

  A delimiter to make the concatenated names unique, as
  `"{name}{index_unique}{key}"`, or `NULL` to keep the names.

- fill_value:

  The value for entries an outer join introduces, see the Arrays
  section.

- pairwise:

  Whether to combine the pairwise mapping of the concatenated axis, see
  the Aligned mappings section.

## Value

An `AnnData`.

## Arrays

With an inner join the names keep the order of the first object. With an
outer join the names are sorted, unless every object has the same names.
An outer join fills the entries it introduces with `fill_value`. The
default is `0` when any of the arrays being combined is sparse and `NA`
otherwise, so dense arrays become floating point. `fill_value` is an
On-disk dtype in Python's terms: an R `integer` is int64, a `double` is
float64 and a `logical` is bool.

Arrays are combined like numpy does. The result has the promoted On-disk
dtype of the inputs, so int32 with float32 gives float64. A result is
sparse (CSR, even for CSC inputs) when any input is sparse and dense
otherwise. An array that only some objects have is kept on an outer
join, with the other objects contributing `fill_value`, and dropped on
an inner join. The same applies to X, and objects without X give a
result without X.

## Annotations

The annotation of the concatenated axis (`obs` for `axis = "obs"`) has
the columns every object has on an inner join and all of them on an
outer join, with `NA` where an object lacks a column. Categorical
columns take the union of the categories in natural order unless some
are ordered, and `bool` columns become nullable boolean when missing
values are introduced. The annotation of the other axis keeps the
columns `merge` selects, from the annotations reindexed to the result's
names. Columns of types that pandas would combine into an `object`
column of mixed values (such as numbers with strings) raise
`anndata_unsupported_value_error`. Keys are character, so numeric `keys`
are converted to strings.

## Merge strategies

`merge` and `uns_merge` are `NULL` (nothing is kept), `"same"` (values
that are the same in every object), `"unique"` (values with one possible
value), `"first"` (the first value) or `"only"` (values in only one
object). `uns_merge` applies them recursively to lists. A function takes
its place: it is called with the list of reindexed annotation data
frames (or of `uns` lists) and returns a data frame or named list (or a
list).

## Aligned mappings

The mapping of the concatenated axis (`obsm` for `axis = "obs"`) is
concatenated for the keys every object has (inner join) or all keys
(outer join). Arrays of different widths are cut to the narrowest on an
inner join and padded to the widest with `fill_value` on an outer join,
and data frames are combined on their columns. The mapping of the other
axis (`varm`) is reindexed to the result's names and selected with
`merge`, so it is empty by default. With `pairwise = TRUE` the pairwise
mapping of the concatenated axis (`obsp`) is combined as a block
diagonal CSR matrix, and otherwise it is empty. The pairwise mapping of
the other axis (`varp`) follows `merge`.

## Raw

When every object has `raw` its `X`, `var` and `varm` are concatenated
with the same `axis`, `join` and other arguments, and the `var` columns
and `varm` entries follow the rules for the other axis above. When only
some objects have `raw` it is dropped with a warning of class
`anndata_missing_raw_warning`.

## Lazy inputs

When every object is read with
[`read_lazy()`](https://lazappi.github.io/R-anndata-claude/reference/read_lazy.md),
`X`, `layers` and the `obsm` arrays stay lazy (`DelayedArray`) and their
realised values equal the in-memory result. When some objects are lazy
and others are not, the lazy ones are read into memory, as Python does.

## Deviations from Python

`obs` and `var` of lazy objects are always read into memory (Python
keeps them lazy, loses their categorical columns and fails on an outer
join with string columns), and a lazy result has DelayedArray's R types,
not the promoted On-disk dtype. Annotation columns Python would turn
into a mixed `object` column raise `anndata_unsupported_value_error`.
See
[`vignette("deviations")`](https://lazappi.github.io/R-anndata-claude/articles/deviations.md)
for the full list.

## Examples

``` r
a <- AnnData(data.frame(x = c(1, 1), y = c(1, 1), row.names = c("a", "b")))
b <- AnnData(data.frame(y = c(2, 2), z = c(2, 2), row.names = c("c", "d")))
concat(list(a, b))$var_names
#> [1] "y"
concat(list(a, b), join = "outer")$X
#>      [,1] [,2] [,3]
#> [1,]    1    1   NA
#> [2,]    1    1   NA
#> [3,]   NA    2    2
#> [4,]   NA    2    2
```
