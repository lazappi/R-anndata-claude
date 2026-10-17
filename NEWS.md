# anndata.claude (development version)

* `adata$chunked_X(chunk_size)` returns the rows of X in chunks (a list of `chunk`, 1-based `start` and `end`) and `adata$chunk_X(select, replace)` returns random rows (a single number) or chosen rows (an index, with `I()` for one row), for backed and in-memory objects and Views.

* A backed `raw` cannot be replaced, `filename <- NULL` loads a backed `raw$X` into memory and setting `raw` on a backed object raises Python's error.

* A backed object can be written with `write()` and `write_h5ad()` (to a new file or in place), copied with `copy(filename)` and loaded with `to_memory()`.

* Writing a backed dense `X` to a new h5ad file copies it in blocks of at least `anndata_settings$min_rows_for_chunked_h5_copy` rows (default 1000) instead of reading it whole.

* In backed mode `adata$X[i, j] <- value` writes into a dense X in `"r+"` mode, assigning X ends backed mode (`isbacked` is `FALSE`, the file is untouched) and changing a View of a backed object fails as in Python.

* `sparse_dataset()` handles have `$append()` to add rows (CSR) or columns (CSC) to a sparse matrix on disk, and sparse matrices written to HDF5 are now resizable like Python's, so the files can be appended to.

* A backed sparse `X` (CSR or CSC) supports `dim()`, `[` with every matrix index form (reading only the needed parts of `data` and `indices`), `as.matrix()`, `$to_memory()` and views, and `sparse_dataset()` makes the same handle for an open rhdf5 group.

* A backed dense `X` supports `dim()`, `[` with every matrix index form (reading only the selected part of the file), `as.matrix()` and views that read only their subset.

* `read_h5ad(backed = "r")` (or `"r+"`) keeps `X` and `raw$X` on disk, with `adata$isbacked`, `adata$filename`, the file manager `adata$file` (`open()`, `close()`, `is_open`) and `backed at '<file>'` in `print()`.

* rec-arrays in zarr now honour the `compressors` dataset argument (zstd, gzip, blosc or none) and read stores Python compressed with any of them.

# anndata.claude 0.0.2

Second milestone: zarr I/O and Views.

* `read_zarr()` and `write_zarr()` (also `adata$write_zarr()`) read and write zarr v3 stores that round trip with Python.
  Dataset arguments `compressors` (zstd, gzip, blosc or none) and `chunks` are supported.
  The settings `zarr_write_format` and `auto_shard_zarr_v3` are added (writing v2 is not yet supported).
  Arrays are sharded like Python's by default, and the `shards` dataset argument sets the shard shape or `NULL` for none.
* rec-arrays in zarr keep their field dtypes (integer widths, float32, bool, fixed-length strings), may have no rows or hold non-ASCII text, and are sharded when `shards` is given.
* `read_zarr()` and `read_elem()` also read zarr v2 stores, including consolidated metadata, blosc compression and rec-arrays.
* `adata[i, j]` returns a View that shares X, layers and the aligned mappings with its parent (as in Python), has `is_view` `TRUE` and prints with a `View of ` prefix.
  Views of Views refer to the original parent, and modifying a View makes it an independent object and leaves the parent unchanged, with Python's `anndata_implicit_modification_warning` messages (R cannot tell `view$obs$col <- x` from `view$obs <- x`, so these always warn).
  Values extracted from a View are plain R objects, so `x <- view$X; x[1, 1] <- 0` does not change the View as it does in Python.
* `adata$write()` is a shortcut for `write_h5ad()`, as in Python.

## Known limitations

* Writing zarr v2 and zip stores (`.zarr.zip`) are not supported.
* rec-arrays in zarr are always compressed with zstd, ignoring `compressors`.
* rec-array field dtypes are still not preserved in h5ad (ADR 0005), and unsorted sparse indices are sorted on read (ADR 0006).
* Legacy formats, backed mode, concatenation and lazy arrays are not yet supported.

# anndata.claude 0.0.1

First milestone: the MVP of an R port of Python anndata 0.13.4, with h5ad files that round trip between R and Python.

## Core object

* `AnnData()` creates an R6 object with reference semantics holding `X`, `obs`, `var`, `obsm`, `varm`, `obsp`, `varp`, `layers`, `uns` and `raw`.
  `obs` and `var` are `S4Vectors::DataFrame`s, and `X` is stored as the `NA` layer.
* Assignment validates and aligns values as Python does, including names, categoricals and the `raw` slot.
* Subsetting with R indexing, `copy()`, `transpose()`/`t()`, `obs_names_make_unique()`, `var_names_make_unique()`, `to_df()`, `strings_to_categoricals()` and `rename_categories()`.
* `print()` matches Python's `repr`.
* Methods that Python deprecates (`obs_vector()`, `var_vector()` and the `*_keys()` methods) warn.
* `anndata_settings()`, `local_anndata_settings()` and `with_anndata_settings()` mirror Python's settings.

## h5ad I/O

* `read_h5ad()` and `write_h5ad()` support every current encoding: dense and sparse arrays, strings, scalars, nullable and categorical arrays, dataframes, dicts, rec-arrays, `AnnData` and `Raw`.
* On-disk dtypes (such as float32, the integer widths and unsigned integers) are recorded on read and restored on write.
* Compression, `as_dense` and `as_sparse` options.

## Known limitations

* rec-array field dtypes are not preserved, and rec-arrays with non-ASCII text, compression or no rows cannot be written (ADR 0005).
* Unsorted sparse indices are sorted on read (ADR 0006).
* Legacy h5ad formats, backed mode, zarr, concatenation and lazy arrays are not yet supported.
