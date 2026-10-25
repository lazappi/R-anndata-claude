# Annotated data matrix

`AnnData()` creates an annotated data matrix of `n_obs` observations by
`n_vars` variables, following Python anndata 0.13.4. It wraps the
`AnnData` R6 class (ADR 0002), so objects have reference semantics:
`b <- a` aliases and does not copy.

## Usage

``` r
AnnData(
  X = NULL,
  obs = NULL,
  var = NULL,
  uns = NULL,
  ...,
  obsm = NULL,
  varm = NULL,
  layers = NULL,
  raw = NULL,
  shape = NULL,
  obsp = NULL,
  varp = NULL,
  filename = NULL,
  filemode = NULL
)
```

## Arguments

- X:

  A numeric or logical matrix, or a `Matrix` sparse matrix, or `NULL`.
  An `AnnData` supplies all its Slots, and then `obs`, `var`, `uns`,
  `obsm`, `varm`, `obsp` and `varp` must not be given. A `data.frame` or
  `DataFrame` is converted to a matrix, with a warning when its columns
  differ in type, and its row and column names become the obs_names and
  var_names. Automatic row names are ignored.

- obs, var:

  Annotations of observations and variables as `NULL`, a named list, a
  `data.frame` or a `DataFrame`. When `X` is a frame with names, these
  must match them, unless they have no names of their own.

- uns:

  Unstructured annotation, a named list or `NULL`.

- ...:

  Must be empty, so that the arguments after `uns` are named.

- obsm, varm, obsp, varp, layers:

  Aligned mappings as named lists or `NULL`. An `NA` name in `layers`
  addresses X.

- raw:

  An `AnnData` or a named list with the elements `X`, `var` and `varm`,
  whose contents become the Raw, or `NULL`. Without `X` the Raw is made
  from the X, var and varm of the new object.

- shape:

  Integer vector `c(n_obs, n_vars)` used when `X` is `NULL`.

- filename, filemode:

  Backed mode (not yet supported).

## Value

An `AnnData` object.

## Details

`X` is stored in the layers storage under the `NA` key (ADR 0004) and
`adata$X` aliases it. The shape comes from `X`, from `shape` or is
inferred from `obs` and `var`. Giving both `shape` and `X` is an error.
Without names, observations and variables are named `"0"`, `"1"`, ...,
`"n-1"` as in Python.

## Fields

- `X`: the data matrix, or `NULL`

- `uns`: unstructured annotation, a named list

- `obs`, `var`: annotation
  [`S4Vectors::DataFrame`](https://rdrr.io/pkg/S4Vectors/man/DataFrame-class.html)s

- `obs_names`, `var_names`: character names

- `n_obs`, `n_vars`, `shape`: dimensions

- `is_view`: whether the object is a View made by `adata[i, j]`

- `isbacked`, `filename` and `file`: whether the object is backed by a
  file (`read_h5ad(backed = )`), the path of that file or `NULL`, and
  the file manager (`file$open()`, `file$close()`, `file$is_open`)

The dimension and backing fields are read-only and assigning to them
raises an `anndata_read_only_error`.

## Backed mode

`read_h5ad(file, backed = "r")` (or `"r+"`) keeps `X` and `raw$X` on
disk and reads every other Slot into memory.
[`print()`](https://rdrr.io/r/base/print.html) shows
`backed at '<file>'`. `adata$file$close()` closes the file but keeps the
object backed, and the next read of `X` opens it again. The file is
closed when the object is garbage collected.

## Views

`adata[i, j]` returns a View that shares data with `adata`, as in
Python. X, `layers`, `obsm`, `varm`, `obsp` and `varp` are read from the
parent on every access, so a View shows later changes to the parent's X.
`obs`, `var`, `uns` and `raw` are snapshots taken when the View is
created. A View of a View refers to the original parent. Modifying a
View turns it into an independent object (`is_view` becomes `FALSE`) and
leaves the parent unchanged. This includes nested forms such as
`view$X[1, 1] <- 0`, `view$obs$col <- x` and `view$uns$k <- v`, and
deleting a key with `view$obsm[["k"]] <- NULL`. Where Python warns, an
`anndata_implicit_modification_warning` is raised. R cannot tell
`view$obs$col <- x` from `view$obs <- x`, so both warn with the message
for assigning the whole Slot. `copy()` of a View returns an independent
object, `transpose()` raises an error, and writing a View to h5ad or
zarr writes the subset.

## Deviations from Python

Accessors return plain R values and not View wrappers. In Python
`x = view.X; x[0, 0] = 1` modifies the View, but in R
`x <- view$X; x[1, 1] <- 1` only changes `x` and the View is unaffected.
Assign through the View (`view$X[1, 1] <- 1`) to modify it. For a View
of a backed object this makes the View independent with a warning, where
Python silently changes nothing. See
[`vignette("deviations")`](https://lazappi.github.io/R-anndata-claude/articles/deviations.md)
for the full list.

## Deprecated methods

**\[deprecated\]**

Python 0.13.4 deprecates these methods, so they warn on every call with
the classes `anndata_deprecated_warning` and `anndata_future_warning`:
`obs_keys()`, `var_keys()`, `obsm_keys()`, `varm_keys()`, `uns_keys()`,
`obs_vector()` and `var_vector()`.

## Examples

``` r
adata <- AnnData(matrix(as.numeric(1:6), nrow = 3))
adata$shape
#> [1] 3 2
adata$obs_names
#> [1] "0" "1" "2"

# From a data frame, whose names are kept
df <- data.frame(a = c(1, 2), b = c(3, 4), row.names = c("r1", "r2"))
AnnData(df)$obs_names
#> [1] "r1" "r2"

# From another AnnData
AnnData(adata)$shape
#> [1] 3 2
```
