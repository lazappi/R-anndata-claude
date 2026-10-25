# Package settings

`anndata_settings` mirrors Python's `anndata.settings`. Each setting is
a field that is read with `anndata_settings$name` and set with
`anndata_settings$name <- value`. Values are stored as R options named
`anndata.claude.<setting>`, so
[`options()`](https://rdrr.io/r/base/options.html) and
[`withr::local_options()`](https://withr.r-lib.org/reference/with_options.html)
work too, and an unset option means the default. Invalid values (and
unknown setting names) raise an error of class
`anndata_invalid_setting_error`.

## Usage

``` r
anndata_settings

local_anndata_settings(new, .local_envir = parent.frame())

with_anndata_settings(new, code)
```

## Format

`anndata_settings` is an environment of class `anndata_settings`.

## Arguments

- new:

  A named list of settings to override.

- .local_envir:

  The environment whose exit restores the settings.

- code:

  Code to run with the overridden settings.

## Value

`with_anndata_settings()` returns the value of `code`.
`local_anndata_settings()` returns the previous values invisibly.

## Details

`anndata_settings$reset()` restores every default.
`with_anndata_settings()` and `local_anndata_settings()` override
settings temporarily, equivalent to `settings.override` in Python, and
restore the previous values on exit even when an error occurs. Printing
`anndata_settings` lists each setting, its value and a description.

## Settings

- `remove_unused_categories` (default `TRUE`): Whether or not to remove
  unused categories with factors.

- `check_uniqueness` (default `TRUE`): Whether or not to check
  uniqueness of the `obs` indices on creation of an `AnnData`.

- `allow_write_nullable_strings` (default `NULL`): Whether or not to
  allow writing of nullable string arrays. When `NULL` it behaves as
  Python with pandas 3 (`infer_string` is true). When `FALSE`
  explicitly, string arrays are written in the old, non-nullable format.

- `disallow_forward_slash_in_h5ad` (default `TRUE`): Whether or not to
  disallow the `/` character in keys for h5ad files.

- `write_csr_csc_indices_with_min_possible_dtype` (default `FALSE`):
  Write a csr or csc matrix with the minimum possible data type for
  `indices`, always unsigned integer.

- `restrict_index_types` (default `TRUE`): Whether to force coercion to
  a string index upon creation of an `AnnData` or setting `obs`/`var`.
  Setting this to `FALSE` allows other index types, but integer indices
  are always converted to strings.

- `zarr_write_format` (default `3`): The zarr format version that
  [`write_zarr()`](https://lazappi.github.io/R-anndata-claude/reference/zarr.md)
  writes. Writing version 2 is not yet supported and raises
  `anndata_not_supported_error`.

- `auto_shard_zarr_v3` (default `TRUE`): Whether zarr v3 arrays are
  sharded automatically, with a target of 1 GB uncompressed per shard.
  An explicit `shards` dataset argument overrides it and it is ignored
  for version 2. Shard shapes can differ from Python's, and rec-arrays
  are not sharded.

- `min_rows_for_chunked_h5_copy` (default `1000`): The least number of
  rows read at once when a dense X on disk is copied to a new h5ad file
  (a chunked source dataset raises it to its chunk length). Writing to a
  compressed dataset copies it chunk by chunk instead.

## Omitted settings

Python's `copy_on_write_X` is deprecated and always on upstream, so it
is omitted (copy-on-write is the only behaviour).
`use_sparse_array_on_read` is omitted because R has no distinction
between scipy sparse matrices and sparse arrays.

## Examples

``` r
anndata_settings$check_uniqueness
#> [1] TRUE

with_anndata_settings(list(check_uniqueness = FALSE), {
  anndata_settings$check_uniqueness
})
#> [1] FALSE

anndata_settings$check_uniqueness <- FALSE
anndata_settings$reset()
anndata_settings
#> <anndata_settings>
#>   remove_unused_categories                       TRUE   Remove unused categories from factors
#>   check_uniqueness                               TRUE   Check uniqueness of obs names on creation
#>   allow_write_nullable_strings                   NULL   Allow writing nullable string arrays (NULL infers it)
#>   disallow_forward_slash_in_h5ad                 TRUE   Disallow `/` in keys for h5ad files
#>   write_csr_csc_indices_with_min_possible_dtype  FALSE  Write sparse indices with the minimum unsigned dtype
#>   restrict_index_types                           TRUE   Force string indices on creation and when setting obs/var
#>   zarr_write_format                              3      Zarr format version written (2 is not yet supported)
#>   auto_shard_zarr_v3                             TRUE   Shard zarr v3 arrays automatically (not yet written)
#>   min_rows_for_chunked_h5_copy                   1000   Rows copied at once from a backed dense X
```
