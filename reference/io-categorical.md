# Categorical arrays

Reads and writes the Element `categorical` (version 0.2.0), a group with
the boolean attribute `ordered` and the members `codes` and
`categories`.

## Usage

``` r
write_factor(store, key, value, dataset_kwargs, path)
```

## Arguments

- store:

  An open rhdf5 file or group handle.

- key:

  Name of the Element within `store`, `"/"` writes into the root.

- value:

  The R value to write.

- dataset_kwargs:

  A list of dataset creation options.

- path:

  Path of the Element within `store`.

## Details

A `factor` is written as an unordered and an `ordered` factor as an
ordered categorical. R levels are always strings, so non-string
categories (Python's integer, float and boolean categories) are read as
the string form of the category and the original categories are kept in
the `anndata_categories` attribute of the factor. They are written back
with their own dtype as long as the levels still match them, and as
strings otherwise (so subsetting a factor with `[` writes string
categories).

Codes use the smallest signed integer dtype pandas picks for the number
of categories, whatever dtype the file had. `NA` is the code -1 and
unused levels are kept.
