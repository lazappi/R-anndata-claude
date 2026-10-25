# Getting started with anndata.claude

anndata.claude is an R port of Python anndata. Its first priority is
that `.h5ad` files round trip between R and Python.

``` r

library(anndata.claude)
```

## Create an AnnData

An `AnnData` holds a matrix `X` with observations (`obs`) as rows and
variables (`var`) as columns.

``` r

X <- matrix(as.numeric(1:12), nrow = 3)
obs <- data.frame(
  cell_type = c("T", "B", "T"),
  row.names = c("cell1", "cell2", "cell3")
)
var <- data.frame(
  highly_variable = c(TRUE, FALSE, TRUE, FALSE),
  row.names = c("gene1", "gene2", "gene3", "gene4")
)
adata <- AnnData(X, obs = obs, var = var)
adata
#> AnnData object with n_obs × n_vars = 3 × 4
#>     obs: 'cell_type'
#>     var: 'highly_variable'
#>     layers: None (.X)
```

## Assign Slots

Annotations are aligned to `obs` or `var` and are kept in `obsm`,
`varm`, `obsp`, `varp` and `layers`. Unstructured data goes in `uns`.

``` r

adata$obsm[["pca"]] <- matrix(c(0.1, 0.2, 0.3, 1, 2, 3), nrow = 3)
adata$layers[["counts"]] <- X * 2
adata$uns[["note"]] <- "example"
adata$obs[["batch"]] <- c("a", "a", "b")
adata
#> AnnData object with n_obs × n_vars = 3 × 4
#>     obs: 'cell_type', 'batch'
#>     var: 'highly_variable'
#>     uns: 'note'
#>     obsm: 'pca'
#>     layers: 'counts', None (.X)
```

## Subset

Indexing is 1-based, and negative indices exclude.

``` r

adata[1:2, ]
#> View of AnnData object with n_obs × n_vars = 2 × 4
#>     obs: 'cell_type', 'batch'
#>     var: 'highly_variable'
#>     uns: 'note'
#>     obsm: 'pca'
#>     layers: 'counts', None (.X)
adata[-1, c("gene1", "gene3")]$shape
#> [1] 2 2
```

Subsetting returns a View, which shares data with the original `AnnData`
and prints with a `View of` prefix. Modifying a View makes it an
independent object and leaves the original unchanged, with a warning.

``` r

sub <- adata[1:2, ]
sub$is_view
#> [1] TRUE
sub$obs[["batch"]] <- c("x", "y")
#> Warning: Trying to modify attribute `.obs` of view, initializing view as
#> actual.
sub$is_view
#> [1] FALSE
adata$obs[["batch"]]
#> [1] "a" "a" "b"
```

Values extracted from a View are plain R objects, so unlike Python
`x <- sub$X; x[1, 1] <- 0` does not change the View. Assign through the
View (`sub$X[1, 1] <- 0`) instead. This and the other differences from
Python are listed in
[`vignette("deviations")`](https://lazappi.github.io/R-anndata-claude/articles/deviations.md).

## Write and read h5ad

``` r

path <- tempfile(fileext = ".h5ad")
write_h5ad(adata, path)
roundtrip <- read_h5ad(path)
roundtrip
#> AnnData object with n_obs × n_vars = 3 × 4
#>     obs: 'cell_type', 'batch'
#>     var: 'highly_variable'
#>     uns: 'note'
#>     obsm: 'pca'
#>     layers: 'counts', None (.X)
identical(roundtrip$obs_names, adata$obs_names)
#> [1] TRUE
```

Use `compression = "gzip"` to compress datasets, and `as_sparse` in
[`read_h5ad()`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md)
to read a dense `X` as a sparse matrix.

## Backed mode

`read_h5ad(backed = "r")` keeps `X` (and `raw$X`) on disk and reads only
the parts that are indexed. Everything else is read into memory. Use
`backed = "r+"` to write changes to `X` back to the file.

``` r

backed <- read_h5ad(path, backed = "r")
backed$isbacked
#> [1] TRUE
backed$filename
#> [1] "/tmp/Rtmpu9A2tJ/file1f385c4b8e42.h5ad"
backed$X[1:2, c(1, 3)]
#>      [,1] [,2]
#> [1,]    1    7
#> [2,]    2    8
```

`chunked_X()` visits the rows of `X` in chunks and `chunk_X()` returns
random or chosen rows.

``` r

chunks <- backed$chunked_X(2)
length(chunks)
#> [1] 2
chunks[[2]]$start
#> [1] 3
backed$chunk_X(I(3))
#>      [,1] [,2] [,3] [,4]
#> [1,]    3    6    9   12
```

`to_memory()` loads the whole object and
[`write_h5ad()`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md)
or `copy(filename)` write a backed object to a new file. Assigning `X`
ends backed mode, and the file is left unchanged.

``` r

in_memory <- backed$to_memory()
in_memory$isbacked
#> [1] FALSE
backed$file$close()
```

[`sparse_dataset()`](https://lazappi.github.io/R-anndata-claude/reference/sparse_dataset.md)
makes a handle on a sparse matrix in an open rhdf5 group, which also has
`$append()` to add rows or columns on disk.

## Move a file to Python and back

The file written above can be read by Python anndata directly. These
chunks need Python so they are shown but not run.

``` python
import anndata as ad

adata = ad.read_h5ad("example.h5ad")
adata.obs["from_python"] = True
adata.write_h5ad("from-python.h5ad")
```

``` r

back <- read_h5ad("from-python.h5ad")
back$obs[["from_python"]]
```

## Write and read zarr

[`write_zarr()`](https://lazappi.github.io/R-anndata-claude/reference/zarr.md)
writes a zarr v3 store (a directory) and
[`read_zarr()`](https://lazappi.github.io/R-anndata-claude/reference/zarr.md)
reads v3 and v2 stores.

``` r

zarr_path <- tempfile(fileext = ".zarr")
write_zarr(adata, zarr_path)
zarr_roundtrip <- read_zarr(zarr_path)
zarr_roundtrip
#> AnnData object with n_obs × n_vars = 3 × 4
#>     obs: 'cell_type', 'batch'
#>     var: 'highly_variable'
#>     uns: 'note'
#>     obsm: 'pca'
#>     layers: 'counts', None (.X)
identical(zarr_roundtrip$obs_names, adata$obs_names)
#> [1] TRUE
```

Use the `compressors` argument to choose the compression (zstd, gzip,
blosc or none) and `shards` to set the shard shape. Writing zarr v2 is
not yet supported.

## Lazy reading

[`read_lazy()`](https://lazappi.github.io/R-anndata-claude/reference/read_lazy.md)
reads an h5ad file or zarr store into an `AnnData` whose `X`, layers,
mappings, `obs` and `var` are lazy. Arrays are `DelayedArray`s (sparse
ones stay sparse) and data frame columns are read when they are used.
`uns` is read into memory.

``` r

lazy <- read_lazy(zarr_path)
class(lazy$X)
#> [1] "DelayedMatrix"
#> attr(,"package")
#> [1] "DelayedArray"
lazy$X[1:2, ]
#> <2 x 4> DelayedMatrix object of type "double":
#>      [,1] [,2] [,3] [,4]
#> [1,]    1    4    7   10
#> [2,]    2    5    8   11
```

Subsetting, Views, `copy()` and [`t()`](https://rdrr.io/r/base/t.html)
stay lazy, and `to_memory()` reads everything. Writing a lazy object is
not supported yet, so call `to_memory()` first.

``` r

lazy_memory <- lazy$to_memory()
class(lazy_memory$X)
#> [1] "matrix" "array"
```

[`read_elem_lazy()`](https://lazappi.github.io/R-anndata-claude/reference/read_elem_lazy.md)
does the same for a single Element, and `chunks` sets the chunk shape of
the `DelayedArray` grid.

``` r

read_elem_lazy(zarr_path, "X", chunks = c(2, NA))
#> <3 x 4> DelayedMatrix object of type "double":
#>      [,1] [,2] [,3] [,4]
#> [1,]    1    4    7   10
#> [2,]    2    5    8   11
#> [3,]    3    6    9   12
```

## Concatenate

[`concat()`](https://lazappi.github.io/R-anndata-claude/reference/concat.md)
combines `AnnData` objects along `axis` (`"obs"` by default) and follows
Python’s
[`concat()`](https://lazappi.github.io/R-anndata-claude/reference/concat.md).
An inner join keeps the variables every object has and an outer join
keeps all of them, filling new entries with `fill_value`.

``` r

a <- AnnData(
  matrix(1, nrow = 2, ncol = 2),
  obs = data.frame(row.names = c("a1", "a2")),
  var = data.frame(row.names = c("g1", "g2"))
)
b <- AnnData(
  matrix(2, nrow = 2, ncol = 2),
  obs = data.frame(row.names = c("b1", "b2")),
  var = data.frame(row.names = c("g2", "g3"))
)
concat(list(a, b))$var_names
#> [1] "g2"
concat(list(a, b), join = "outer")$X
#>      [,1] [,2] [,3]
#> [1,]    1    1   NA
#> [2,]    1    1   NA
#> [3,]   NA    2    2
#> [4,]   NA    2    2
```

A named list gives the `keys`, which `label` stores in `obs` and
`index_unique` adds to the names.

``` r

combined <- concat(
  list(first = a, second = b),
  label = "batch",
  index_unique = "-"
)
combined$obs
#> DataFrame with 4 rows and 1 column
#>              batch
#>           <factor>
#> a1-first    first 
#> a2-first    first 
#> b1-second   second
#> b2-second   second
```

`merge` and `uns_merge` choose which annotations of the other axis and
which `uns` entries are kept (`"same"`, `"unique"`, `"first"` or
`"only"`, or a function). Views and backed objects can be concatenated,
and objects from
[`read_lazy()`](https://lazappi.github.io/R-anndata-claude/reference/read_lazy.md)
give a lazy result.

## Other formats

[`read_text()`](https://lazappi.github.io/R-anndata-claude/reference/read_text.md)
and
[`read_csv()`](https://lazappi.github.io/R-anndata-claude/reference/read_text.md)
read delimited text, from a path or a character vector of lines. The
first column holds the `obs` names when it is not numeric and `dtype`
(default `"float32"`) sets the type of X.

``` r

lines <- c("cell,g1,g2", "c1,1,2", "c2,3,4")
read_csv(lines)$to_df()
#>    g1 g2
#> c1  1  2
#> c2  3  4
```

[`read_mtx()`](https://lazappi.github.io/R-anndata-claude/reference/read_mtx.md)
(Matrix Market),
[`read_umi_tools()`](https://lazappi.github.io/R-anndata-claude/reference/read_umi_tools.md),
[`read_hdf()`](https://lazappi.github.io/R-anndata-claude/reference/read_hdf.md)
and
[`read_excel()`](https://lazappi.github.io/R-anndata-claude/reference/read_excel.md)
(needs readxl) read other sources, and all return an `AnnData`.
[`read_umi_tools()`](https://lazappi.github.io/R-anndata-claude/reference/read_umi_tools.md)
gives a sparse X with sorted names.

``` r

path <- tempfile(fileext = ".tsv")
writeLines(
  c("gene\tcell\tcount", "g2\tc2\t3", "g1\tc1\t1", "g3\tc1\t2"),
  path
)
read_umi_tools(path)
#> AnnData object with n_obs × n_vars = 2 × 3
#>     layers: None (.X)
```

[`write_csvs()`](https://lazappi.github.io/R-anndata-claude/reference/write_csvs.md)
writes `obs`, `var`, `obsm`, `varm` and `uns` (and X with
`skip_data = FALSE`) as csv files that pandas reads the same as Python’s
output.

``` r

dir <- tempfile("csvs")
write_csvs(adata, dir)
list.files(dir, recursive = TRUE)
#> [1] "obs.csv"      "obsm.csv"     "uns/note.csv" "var.csv"      "varm.csv"
unlink(dir, recursive = TRUE)
```

## Move a zarr store to Python and back

Python anndata reads and writes the same store. These chunks need Python
so they are shown but not run.

``` python
import anndata as ad

adata = ad.read_zarr("example.zarr")
adata.obs["from_python"] = True
adata.write_zarr("from-python.zarr")
```

``` r

back <- read_zarr("from-python.zarr")
back$obs[["from_python"]]
```
