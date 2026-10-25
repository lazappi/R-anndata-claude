# Aligned mappings: obsm, varm, obsp and varp

Internal R6 class behind `adata$obsm`, `adata$varm`, `adata$obsp` and
`adata$varp`, following `src/anndata/_core/aligned_mapping.py`. Axis
arrays (obsm and varm) need a first dimension equal to n_obs or n_vars,
and accept a `data.frame` or `DataFrame` whose row names equal the
obs_names or var_names. Pairwise arrays (obsp and varp) need both
dimensions equal to n_obs or n_vars. A plain numeric or logical vector
becomes a one column matrix, as a 1-D numpy array does in Python.

## Arguments

- key:

  A single non-empty string.

- value:

  The value to store, or `NULL` to remove `key`.

- call:

  The call reported by conditions.

## Details

The mapping supports `[[`, `$`, `[[<-`, `$<-`,
[`names()`](https://rdrr.io/r/base/names.html),
[`length()`](https://rdrr.io/r/base/length.html) and
[`as.list()`](https://rdrr.io/r/base/list.html), and assigning `NULL`
removes a key. `$` looks up keys first, so a key named like a method
(`get`, `set`, `remove`, `replace`, `keys`) hides it, and `[[` is always
safe.
