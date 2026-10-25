# Read an HDF5 file with a data matrix

`read_hdf()` reads the dataset `key` of an HDF5 (`.h5`) file into the X
of an
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
object, as Python's `read_hdf()`. If the file also has the datasets
`row_names` and `col_names` they become the `obs` and `var` names.

## Usage

``` r
read_hdf(filename, key)
```

## Arguments

- filename:

  A path to the HDF5 file.

- key:

  The name of the dataset holding the matrix. An empty string is an
  error that lists the datasets in the file.

## Value

An
[`AnnData()`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)
object.

## Examples

``` r
path <- tempfile(fileext = ".h5")
rhdf5::h5createFile(path)
rhdf5::h5write(matrix(c(0.5, 1.5, 2.5, 3.5), 2), path, "data")
read_hdf(path, "data")
#> AnnData object with n_obs × n_vars = 2 × 2
#>     layers: None (.X)
```
