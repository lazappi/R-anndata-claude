# anndata.claude (development version)

* A sparse matrix with out-of-range `indices` (such as the 1-based indices Illumina DRAGEN 4.5.4 writes) raises an error saying so, with a hint when they look 1-based, and is listed in `vignette("deviations")` (Python reads it into an invalid matrix).

# anndata.claude 0.0.6

Sixth milestone: hardening (performance, documentation and deviations).

* `vignette("deviations")` lists every documented difference from Python anndata 0.13.4 with its reason, and help pages with a deviation link to it.
* Every exported help page has runnable examples, including `read_excel()`.
* Large files are faster to write and to read from zarr: on an 800 MB h5ad (84k cells, 4 GB after rewriting), `write_h5ad()` is about 3x faster and `read_zarr()` about 2x faster.
* A pkgdown site config (`_pkgdown.yml`) groups the reference by area and lists both vignettes as articles, the site URL is a placeholder.

## Known limitations

* Reading is slower than Python on large files (about 5x for `read_h5ad()` and 8x for `read_zarr()`), see `.scratch/hardening/benchmarks.md`.
* Loom is not supported (deprecated in Python), and complex Matrix Market files raise an error (Python silently drops the imaginary part).
* Files from anndata before 0.6 and 0.6.x zarr stores are not supported.
* Writing zarr v2 and zip stores (`.zarr.zip`) are not supported.
* Unsorted sparse indices are sorted on read (ADR 0006).
* A lazily read int32 array holding -2^31 cannot be realised lazily, read it with `read_h5ad()` or `read_zarr()` instead.

# anndata.claude 0.0.5

Fifth milestone: other formats.

* `read_text()` and `read_csv()` read delimited text into an `AnnData` like Python, from a path (plain, `.gz` or `.bz2`), a connection or a character vector of lines, with numpy `dtype` strings (default `"float32"`).
* `read_mtx()` reads Matrix Market files (coordinate or array, integer, real or pattern, `.gz` or `.bz2`) into an `AnnData` with a CSR X like Python, with numpy `dtype` strings (default `"float32"`).
  Complex fields are not supported.
* `read_umi_tools()` reads a umi_tools count table (plain or `.gz`) into an `AnnData` with a CSR X and sorted `obs` and `var` names like Python.
* `read_hdf()` reads a dataset of an HDF5 file into the X of an `AnnData` like Python, using the `row_names` and `col_names` datasets as `obs` and `var` names when present.
* `read_excel()` reads an `.xlsx` sheet into an `AnnData` like Python (first column `obs` names, first row `var` names) using readxl (a suggested package).
  `dtype` is ignored as in Python and names are always strings.
* `write_csvs()` and `adata$write_csvs()` write `obs`, `var`, `obsm`, `varm`, `uns` (and X with `skip_data = FALSE`) as csv files that pandas reads the same as Python's, with Python's `anndata_write_warning` for sparse and unwritable `uns` values.
  A dict in `uns` is written as Python's `repr`, which supports strings, scalars, nested dicts and 1-d arrays that fit on one line.

## Known limitations

* Loom is not supported (deprecated in Python), and complex Matrix Market files raise an error (Python silently drops the imaginary part).
* Files from anndata before 0.6 and 0.6.x zarr stores are not supported.
* Writing zarr v2 and zip stores (`.zarr.zip`) are not supported.
* Unsorted sparse indices are sorted on read (ADR 0006).
* A lazily read int32 array holding -2^31 cannot be realised lazily, read it with `read_h5ad()` or `read_zarr()` instead.

# anndata.claude 0.0.4

Fourth milestone: files from old anndata releases and full rec-array fidelity.

* Files from old anndata releases read their `obs` and `var` as Python does: compound datasets (anndata before 0.7), `dataframe` version 0.1.0 groups and categories kept in `uns` (`<col>_categories`), each with Python's `anndata_old_format_warning`.
* Old files with `raw.X`, `raw.var` and `raw.varm` as root members read into `raw`, and `connectivities` and `distances` kept in `uns$neighbors` move to `obsp` with an `anndata_future_warning`.
* Old files with `obsm` and `varm` stored as compound datasets (such as the PBMC 3k example of cellxgene) read as a matrix per field.
* Numeric fields of legacy compound datasets (`obs`, `var`, `uns`, `obsm`) keep their on-disk dtype, such as float32.
* Old files read in backed mode (`read_h5ad(backed = "r")`) with their unencoded dense or h5sparse `X` left on disk.
  `read_lazy()` reads only current encodings like Python and no longer moves `uns$neighbors` matrices to `obsp`.
* rec-arrays in h5ad keep their field dtypes (integer widths and signedness, float32, bool, fixed-length and variable-length strings) on read and write, text is written as variable-length UTF-8 like h5py, and rec-arrays with no rows or `compression = "gzip"` can be written (`"lzf"` writes them uncompressed).
* The package now has compiled code, a small C helper linked to Rhdf5lib for compound types (ADR 0008), so installing from source needs a C compiler.

## Known limitations

* Other formats (csv, mtx, text, excel, umi_tools and hdf) are not yet supported, and loom will not be (deprecated in Python).
* Files from anndata before 0.6 and 0.6.x zarr stores are not supported.
* Writing zarr v2 and zip stores (`.zarr.zip`) are not supported.
* Unsorted sparse indices are sorted on read (ADR 0006).
* A lazily read int32 array holding -2^31 cannot be realised lazily, read it with `read_h5ad()` or `read_zarr()` instead.

# anndata.claude 0.0.3

Third milestone: backed mode, lazy reading and concatenation.

* `concat()` combines `AnnData` objects along `axis` with an inner or outer `join`, stacking X and the layers like Python (numpy dtype promotion, CSR for any sparse input, `fill_value` for outer joins). The `obs` and `var` annotations are combined (categoricals, nullable boolean promotion), with `merge` and `uns_merge` strategies or functions, `label`, `keys` (or a named list) and `index_unique`. The aligned mappings (`obsm`, `varm`, `obsp`, `varp`), `pairwise` and `raw` are combined like Python (`raw` is dropped with a warning when only some objects have one). Views and backed objects can be concatenated (backed `X` is read into memory, as Python does). Lazily read objects (`read_lazy()`) give a lazy `X`, `layers` and `obsm` (their `obs` and `var` are read into memory).

* The vignette has a section on lazy reading.

* `read_lazy()` (experimental) reads an h5ad file or zarr store as an `AnnData` with lazy X, layers, obsm, varm, obsp, raw, obs and var. `to_memory()` reads everything into memory, `copy()` keeps it lazy, and writing a lazy object (or a View of one) raises Python's not-implemented error until `to_memory()` is used.

* `read_elem_lazy()` (experimental) reads an Element of an h5ad file or zarr store lazily: arrays are `DelayedArray`s (sparse ones stay sparse), and categorical, nullable and `dataframe` Elements have lazy columns.

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

## Known limitations

* Legacy formats (files from older anndata versions) and other formats (csv, mtx, loom and others) are not yet supported.
* Writing zarr v2 and zip stores (`.zarr.zip`) are not supported.
* rec-array field dtypes are still not preserved in h5ad (ADR 0005), and unsorted sparse indices are sorted on read (ADR 0006).
* A lazily read int32 array holding -2^31 cannot be realised lazily, read it with `read_h5ad()` or `read_zarr()` instead.

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
