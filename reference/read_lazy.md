# Read an AnnData lazily

`read_lazy()` reads an h5ad file or a zarr store (v3 or v2) into an
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
whose `X`, `layers`, `obsm`, `varm`, `obsp`, `varp`, `obs`, `var` and
`raw` are lazy (see
[`read_elem_lazy()`](https://lazappi.github.io/R-anndata-claude/reference/read_elem_lazy.md))
and whose `uns` is read into memory. It matches Python's `read_lazy()`.

## Usage

``` r
read_lazy(store, load_annotation_index = TRUE)
```

## Arguments

- store:

  An h5ad file or a zarr directory, given as a path or as an open store
  handle.

- load_annotation_index:

  Whether the `obs` and `var` indexes are read into memory. If `FALSE`
  the names are Python's dummy range (`"0"`, `"1"`, ...).

## Value

An
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md).

## Details

Like Python it only reads the current encodings, so files from old
anndata releases (such as an unencoded `X`, a `dataframe` version 0.1.0
or `raw.X`) raise an `anndata_error`, and `uns$neighbors` matrices are
not moved to `obsp`. Use
[`read_h5ad()`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md)
or
[`read_zarr()`](https://lazappi.github.io/R-anndata-claude/reference/zarr.md)
for those files, which raise `anndata_old_format_warning` (Python's
`OldFormatWarning`).

**\[experimental\]**

## Deviations from Python

Arrays inside `uns` are read into memory (Python keeps them as dask
arrays), [`t()`](https://rdrr.io/r/base/t.html) of a lazy `AnnData`
stays lazy (it fails in Python) and lazy frames are indexed by row name
where Python's `Dataset2D` has no `loc`. See
[`vignette("deviations")`](https://lazappi.github.io/R-anndata-claude/articles/deviations.md)
for the full list.

## Examples

``` r
adata <- AnnData(matrix(as.numeric(1:6), nrow = 3))
path <- tempfile(fileext = ".zarr")
write_zarr(adata, path)
read_lazy(path)
#> AnnData object with n_obs × n_vars = 3 × 2
#>     layers: None (.X)
```
