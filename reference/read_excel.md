# Read an Excel sheet with a data matrix

`read_excel()` reads a sheet of an `.xlsx` file into an
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
object with a dense X, as Python's `read_excel()`. The first column
holds the `obs` names and the first row the `var` names, and the name in
the corner becomes the `obs` index name. It needs the readxl package.

## Usage

``` r
read_excel(filename, sheet, dtype = "float32")
```

## Arguments

- filename:

  A path to the `.xlsx` file.

- sheet:

  The name of the sheet, or its position as a zero-based whole number
  (as Python).

- dtype:

  Ignored, kept for compatibility with Python.

## Value

An
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
object.

## Details

Every other cell must be a number (or empty, which gives `NA`). X has
the dtype `"int64"` when the whole sheet holds whole numbers and
`"float64"` otherwise. Python gives an `object` array when the first
column is text and ignores `dtype`, so R gives doubles whatever the
cells hold and also ignores it. Names are always strings, even with the
setting `restrict_index_types` off (Python then keeps the type of the
labels).

## Deviations from Python

Python's `object` X (text in the first column) has no R form, so X is
numeric, and names are always strings. See
[`vignette("deviations")`](https://lazappi.github.io/R-anndata-claude/articles/deviations.md)
for the full list.

## Examples

``` r
path <- readxl::readxl_example("datasets.xlsx")
# The first column (mpg) becomes the observation names, which repeat here
adata <- suppressWarnings(read_excel(path, sheet = "mtcars"))
adata
#> AnnData object with n_obs × n_vars = 32 × 10
#>     layers: None (.X)
```
