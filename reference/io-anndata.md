# AnnData and Raw

Reads and writes the Elements `anndata` and `raw`, both version 0.1.0.
Both are groups holding one Element per Slot.

## Usage

``` r
check_x_and_layers_are_2d(adata, call = rlang::caller_env())

write_anndata(store, key, value, dataset_kwargs, path)

write_raw(store, key, value, dataset_kwargs, path)
```

## Arguments

- adata:

  An `AnnData`.

- call:

  The call reported by errors.

- store:

  An open rhdf5 file or group handle.

- key:

  Name of the Element within `store`, `"/"` writes into the root.

- value:

  An `AnnData` or `Raw`.

- dataset_kwargs:

  A list of dataset creation options.

- path:

  Path of the Element.

## Details

An `anndata` group has `X`, `obs`, `var`, `obsm`, `varm`, `obsp`,
`varp`, `layers`, `uns` and `raw`. The `NA` layer (X, ADR 0004) is
written to `X` and never inside `layers`. `obsm`, `varm`, `obsp`,
`varp`, `layers` and `uns` are always written as `dict` groups, even
when empty, as Python does. A missing `X` is not written, and a group
without `X` reads as `NULL`. A `raw` group has `X`, `var` and `varm`,
and is read as an `AnnData` that the `raw` argument of
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
accepts.

`X` and every layer must have at most 2 dimensions to be written,
otherwise `anndata_non_2d_error` is raised
(`_check_x_and_layers_are_2d_on_write`).
