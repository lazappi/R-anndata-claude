# Raw

Internal R6 class behind `adata$raw`, following
`src/anndata/_core/raw.py`. A Raw holds `X`, `var` and `varm` and shares
its observations with the parent `AnnData`, so `obs_names` and `n_obs`
come from the parent.

## Arguments

- parent:

  The `AnnData` the Raw belongs to.

- X:

  The raw data matrix with `n_obs` rows, or `NULL` to take X, var and
  varm from `parent`.

- var:

  Variable annotation, as for
  [`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md).

- varm:

  Aligned mapping or named list of arrays with a row per variable.

- from_parent:

  Whether to take X, var and varm from `parent`.

- call:

  The call reported by conditions.

## Details

Without `X` the Raw is built from the parent's own `X`, `var` and
`varm`, which is also what Python does when `adata$raw <- other` is
given an `other` whose `X` is `NULL`.

`raw[i, j]` subsets with R indices (see `anndata-index`) and never drops
dimensions. The result belongs to a copy of the parent restricted to the
observations in `i`, and keeps `varm` rows in step with `j`. `raw[i]`
subsets observations only.

`var` and `X` may be assigned, which is what `raw$var$col <- v` needs,
and an assigned value is validated against the other Slots of the Raw.
In Python they are read-only properties that are modified in place.
