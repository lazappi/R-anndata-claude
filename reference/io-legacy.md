# Unencoded Elements

Reads Elements written without `encoding-type` and `encoding-version`
attributes (`read_basic`), as old anndata releases did. Each one raises
`anndata_old_format_warning`, as Python's `OldFormatWarning`. A group is
read as a dict and a dataset as an array or scalar, and a group with the
h5sparse attributes `h5sparse_format` and `h5sparse_shape` is read as a
CSR or CSC matrix. A compound dataset with array-valued fields (old
`obsm` and `varm`) is read as a list of matrices, one per field. The
member types of a compound dataset come from the compiled helper (ADR
0008), so numeric fields keep their on-disk dtype records (such as
float32). Writing always uses the current encodings.

## Usage

``` r
read_unencoded_elem(elem, path, store, call)
```

## Arguments

- elem:

  An open group or dataset handle.

- path:

  Path of the Element.

- store:

  The store `elem` was opened from.

- call:

  The call reported by conditions.

## Details

Legacy files also read with `read_h5ad(backed = )` (an unencoded dense
`X` or h5sparse `X` stays on disk) and rewrite to the current encodings.
[`read_lazy()`](https://lazappi.github.io/R-anndata-claude/reference/read_lazy.md)
follows Python and only reads the current encodings, so it raises for
the legacy layouts, and it does not move `uns$neighbors` matrices to
`obsp`.
