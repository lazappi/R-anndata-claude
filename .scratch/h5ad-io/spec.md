# h5ad I/O

Status: ready-for-agent

Sub-project 3 of the roadmap (`.scratch/roadmap/spec.md`) and the second half of the MVP.
It reads and writes `.h5ad` files so that a Round trip between R and Python (in either direction, any number of times) preserves every Element.

Python references are relative to `.reference/anndata/`.
The authoritative format description is `docs/fileformat-prose.md`, written below as `fileformat`.
Element read/write code is in `src/anndata/_io/specs/methods.py` (written as `methods.py`) and `src/anndata/_io/specs/registry.py` (written as `registry.py`).

## Scope

In:

- An element registry that dispatches on Encoding type and Encoding version for reading, and on R value for writing
- Reading and writing every current encoding except `awkward-array`
- `read_h5ad()`, `write_h5ad()` (function and `AnnData` method), `read_elem()`, `write_elem()` and the `unwriteable()` method
- On-disk dtype preservation
- HDF5 compression options
- The fixture set and the round-trip test suite
- The package vignette

Out:

- Legacy layouts: `dataframe` 0.1.0, unencoded elements (`IOSpec("", "")`, `methods.py:202-204`) and old categorical storage (`legacy-formats`).
  Reading one raises a classed error that names the path and says legacy files are not yet supported.
- `awkward-array` (`experimental`).
  Reading one raises a classed error.
- `backed = "r"/"r+"` (`backed`), `read_elem_lazy` (`lazy`) and `read_elem_partial` (`backed`)
- zarr (`zarr-io`)

## HDF5 binding

- Use `rhdf5` (with `rhdf5filters` for lzf and other filters) for all HDF5 access
- The first ticket is a spike that confirms rhdf5 can read and write each of these exactly as h5py does:
  - variable-length UTF-8 string datasets and attributes
  - h5py's boolean enum type
  - every integer and float width, signed and unsigned
  - complex numbers (h5py compound `r`/`i`)
  - structured (compound) datasets for `rec-array`
  - 0-dimensional (scalar) datasets
  - array-valued attributes such as `column-order`
- Where rhdf5 cannot do something, the spike documents it and proposes a workaround (e.g. lower-level `H5T`/`H5D` calls).
  If none exists, the spike stops and asks the human.
- Arrays are row-major on disk and R is column-major.
  The shape seen by Python must equal `dim()` in R for every array, with no silent transposition of meaning.

## Encodings

Every encoding below is read and written.
Version numbers are exact, and an unknown Encoding type or version raises `anndata_io_registry_error` naming the path, type and version (as `IORegistryError` does).

| Encoding type | Version | fileformat section | `methods.py` | R value |
| ------------- | ------- | ------------------ | ------------ | ------- |
| `anndata` | 0.1.0 | Elements (`:17-94`) | `:331-386` | `AnnData` |
| `raw` | 0.1.0 | Elements | `:359-408` | `Raw` |
| `dict` | 0.1.0 | Mappings (`:288-335`) | `:437-465` | named list |
| `null` | 0.1.0 | | `:410-436` | `NULL` |
| `array` | 0.2.0 | Dense arrays (`:95-142`) | `:466-622` | numeric, integer, logical or complex vector, matrix or array |
| `string-array` | 0.2.0 | String arrays (`:443-485`) | `:623-722` | character vector, matrix or array |
| `rec-array` | 0.2.0 | | `:723-760` | an R structure representing a structured array (see below) |
| `csr_matrix` | 0.1.0 | Sparse arrays (`:143-208`) | `:867-989` | `dgRMatrix` / `lgRMatrix` |
| `csc_matrix` | 0.1.0 | Sparse arrays | `:867-989` | `dgCMatrix` / `lgCMatrix` |
| `dataframe` | 0.2.0 | DataFrames (`:209-287`) | `:1038-1132` | `DataFrame` (and `data.frame` on write) |
| `categorical` | 0.2.0 | Categorical arrays (`:392-442`) | `:1180-1227` | `factor` / `ordered` |
| `nullable-integer` | 0.1.0 | Nullable (`:486-596`) | `:1228-1335` | integer with `NA` |
| `nullable-boolean` | 0.1.0 | Nullable | `:1228-1335` | logical with `NA` |
| `nullable-string-array` | 0.1.0 | Nullable | `:1228-1360` | character with `NA` |
| `numeric-scalar` | 0.2.0 | Scalars (`:336-391`) | `:1362-1448` | length-1 numeric, integer, logical or complex |
| `string` | 0.2.0 | Scalars | `:1449-1470` | length-1 character |
| `bytes` | 0.2.0 | | `:1459` | read only, as Python does |

Line ranges are approximate starting points, so read the surrounding code too.

## Choosing an encoding on write

The governing rule is that R writes what the reference environment writes for the equivalent Python value.

- The first h5ad-io ticket after the spike builds an **encoding table**.
  For each R value class it records the equivalent Python value and the Encoding type, Encoding version, On-disk dtype and HDF5 attributes that Python 0.13.4 writes for it, observed by actually writing from the reference environment.
  The table is committed at `.scratch/h5ad-io/encoding-table.md` and its cases become fixtures.
- Known constraints the table must respect:
  - Python's dataframe writer has its own rules for string, nullable and categorical columns, including `allow_write_nullable_strings` (`methods.py:1228-1311`).
    R `character` columns follow what Python writes for the pandas 3 default `str` dtype.
  - The obs/var index is always written as Python writes an index (`methods.py:1038-1091`), including the `_index` attribute and the index name
  - `column-order` preserves column order
  - Categorical codes use the smallest integer dtype Python would use, and categories keep their dtype
  - `logical` without `NA` is written as h5py's boolean, and with `NA` as `nullable-boolean`
  - `integer` with `NA` is written as `nullable-integer`
  - Double `NA_real_` and `NaN` are both written as NaN.
    On read, NaN becomes `NaN`, and this NA/NaN collapse is documented as an unavoidable deviation.
  - Complex values use h5py's complex layout, and only complex128 is written.
    complex64 cannot be read correctly by rhdf5, so reading it raises a classed error naming the path.
  - `allow_write_nullable_strings` is honoured as in Python: with `FALSE`, string columns and the index without missing values are written as `string-array`, and a string column with missing values raises the error Python raises
  - A data frame with `NULL` row names (e.g. in obsm or uns) is written as Python writes a `RangeIndex`: an int64 `array` `_index` of `0` to `n - 1`
- **Scalars vs arrays** (Python's behaviour, since R has no scalars):
  - an Element read from disk remembers its Encoding type and is written back with the same one
  - a new length-1 atomic vector with no `dim` is written as `numeric-scalar` or `string`
  - a length-1 vector with a `dim` attribute (or wrapped with the exported helper `as_array()`) is written as a 1-element `array` or `string-array`
- **Unencodable values** (functions, environments, unnamed or partly named lists, `Date`, `POSIXct`, other S4 or S3 objects without an encoding) raise `anndata_io_registry_error`, naming the Element path and the R class.
  Nothing is skipped silently.
  An option to skip with a warning is added only if a later ticket needs it.
- Keys containing `/` raise an error when `disallow_forward_slash_in_h5ad` is on (`_check_has_no_slash_key`, `src/anndata/_io/utils.py:283`)

## On-disk dtype preservation

- Reading records each Element's On-disk dtype where R's native type differs (float32, int8, int16, int64, the unsigned integers, and sparse `indices`/`indptr` dtypes)
- Writing an Element that carries a record restores that dtype, as long as the values are still representable.
  If they are not (e.g. a value no longer fits in uint8), the write raises a classed error naming the path.
  It never truncates or wraps silently.
- Elements without a record are written with R's native types (float64, int32, bool, UTF-8 strings), which is what Python would write for the equivalent values
- 64-bit integers must not silently lose precision.
  int64 and uint64 values are read as double when every value has magnitude below 2^53, and otherwise reading raises a classed error naming the path.
  `bit64` is not a dependency, and the On-disk dtype record restores int64 or uint64 on write (decided in the encoding table).
- R's `NA_integer_` shares its bit pattern with the int32 value -2147483648.
  An int32 dataset containing that value is read as double (keeping the int32 record so it writes back unchanged), never as `NA`.
- Unsorted sparse indices are sorted on read and so written back sorted (ADR 0006)
- `write_csr_csc_indices_with_min_possible_dtype` is honoured (`methods.py:867-968`)
- The mechanism (attributes, a wrapper class or similar) is an implementation choice.
  It must survive the operations in `core-object` (subset, copy, transpose) and must be invisible to normal use: arithmetic and printing behave as with an ordinary R vector or matrix.

## rec-array

rhdf5 cannot inspect or build compound field types, so `rec-array` field dtypes are not preserved (ADR 0005).
Within that limit, compatibility is maximised:

- A `rec-array` is read into an R structure that keeps field names, field order and values (a `data.frame` with a marker class is the expected choice)
- Writing that structure produces a `rec-array` that Python reads, with the same field names, order and values.
  Fields are int32, float64 or fixed-length strings, as rhdf5's compound writer allows.
  Fixed-length string fields are sized to the longest value in bytes, so non-ASCII text survives.
- The deviation is documented in the help for reading and writing, and in the vignette
- Round-trip tests for `rec-array` check that the values of every field are equal in every direction.
  Structural equivalence is relaxed for `rec-array` field types only, and the relaxation is explicit in the test helper so it cannot hide other differences.
- Full field dtype fidelity is the follow-up ticket h5ad-io/15

## Public functions

Python references: `src/anndata/_io/h5ad.py` (written as `h5ad.py`) and `registry.py`.

- `read_h5ad(filename, as_sparse = character(), as_sparse_fmt = c("csr", "csc"), chunk_size = 6000)` (`h5ad.py:214-311`).
  `backed` errors with "not yet supported" until the `backed` sub-project.
- `write_h5ad(adata, filename, compression = NULL, compression_opts = NULL, as_dense = character(), convert_strings_to_categoricals = TRUE)`, also available as `adata$write_h5ad(filename, ...)` (`h5ad.py:51-136`, `anndata.py:1651-1745`)
  - as in Python, `convert_strings_to_categoricals = TRUE` modifies the object in place, including `raw$var`
  - `compression` accepts `"gzip"` and `"lzf"`, and `compression_opts` gives the gzip level
  - `as_dense` accepts only `"X"` and `"raw/X"` (or `"raw.X"`), with Python's errors
  - X and layers with more than 2 dimensions raise an error (`_check_x_and_layers_are_2d_on_write`)
  - scalars are never compressed, matching Python
- `read_elem(file, path)` and `write_elem(file, path, value, dataset_kwargs = list())` work on an open rhdf5 file or group and a path within it (`registry.py:424-549`).
  Writing to `"/"` follows Python's rules (release note 0.13.0).
- `adata$unwriteable(store_type = NULL)` reports whether the object can be written, following `anndata.py:1492-1577`
- The root group gets `encoding-type: anndata` and `encoding-version: 0.1.0`
- obsm, varm, obsp, varp, layers and uns are always written as `dict` groups, even when empty, as Python does.
  The fixtures confirm the exact layout for empty Slots.
- The `NA` layer (X, ADR 0004) is written to `/X` and never inside `/layers`, as Python does with `layers[None]` (`h5ad.py:96-106`)
- Reading a file with no `X` gives `adata$X` equal to `NULL`
- Files with a higher-than-2-D X or layer read with a warning, as in Python (release note 0.13.0)

## Fixtures

`tests/python/generate_fixtures.py` writes one file per case into `tests/testthat/fixtures/h5ad/`, plus a JSON manifest describing each case's expected R-side values where they are not self-evident.
Cases must cover at least:

- One file per row of the encoding table (each R class and its Python equivalent)
- Every numeric dtype as a dense array, a sparse matrix (CSR and CSC, including min-dtype indices) and a scalar
- Dataframes with every column type: numeric of each dtype, bool, string, nullable integer, nullable boolean, nullable string (`NA` and `NaN` na-value), categorical with string and with numeric categories, ordered categorical, and categorical with missing values
- Index edge cases: a named index, duplicate names, `NA` names, non-ASCII names, a column with the same name as the index
- Nested uns with every scalar and array type, empty dicts, `null` values and rec-arrays (including a scanpy `rank_genes_groups`-shaped example)
- raw present with its own var and varm
- Empty and degenerate shapes: 0 observations, 0 variables, no X, and empty Slots
- A realistic object from `anndata.tests.helpers.gen_adata` (`src/anndata/tests/helpers.py:304`) restricted to supported encodings
- Compressed (gzip and lzf) variants of the realistic object

## Round-trip tests

For every fixture:

1. **Python → R**: R reads the file and the result matches the expected R values
2. **Python → R → Python**: R writes the object read in step 1.
   `expect_structurally_equivalent()` passes against the original, and `expect_python_equal()` passes.
3. **R → Python → R**: an equivalent object built in R is written by R, read and rewritten by Python (`tests/python/rewrite.py`), and read again by R, giving an object identical to the one R built

Also:

- R → R round trip of objects built in R, for every supported R value class
- Writing every unencodable value class raises the classed error with the correct path
- Reading legacy and awkward-array Elements raises the "not yet supported" errors
- Every error and warning in `write_h5ad()` and `read_h5ad()`

Live-Python tests use `skip_if_no_python()`.
The committed fixtures and R-side expectations keep step 1 and the R → R tests running offline.

## Vignette

`vignettes/anndata-claude.Rmd` covers creating an `AnnData`, assigning Slots, subsetting, writing and reading h5ad, and moving a file to Python and back.
Code that needs Python is shown but not evaluated.

## Acceptance criteria

- Every encoding in scope reads and writes correctly, with all three round-trip directions passing for every fixture
- The encoding table is committed and matches the tests
- `scripts/check.sh` passes, and the coverage target is met for the MVP
- A real-world file (e.g. scanpy's `pbmc3k_processed`, downloaded in a test that skips offline) reads and round trips with Structural equivalence
