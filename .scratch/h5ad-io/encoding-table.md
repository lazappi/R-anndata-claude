# Encoding table

Findings for `.scratch/h5ad-io/issues/02-encoding-table.md`.
Every row below is observed by writing the Python value with anndata 0.13.4 (pandas 3.0.6, numpy 2.5.4, h5py 3.16.0) and reading the file back with h5py.

The observed table at the end is generated from the fixtures with `tests/python/encoding_table.py` (`uv run --project tests/python python -I tests/python/encoding_table.py tests/testthat/fixtures .scratch/h5ad-io/encoding-table.md`).
The fixture cases are in `tests/python/generate_fixtures.py` and the files are `tests/testthat/fixtures/h5ad/<case>.h5` (an Element at key `x`) or `<case>.h5ad` (a whole object).
In the table a node is shown as `encoding-type version: on-disk dtype [shape] = small values`, groups list their members in braces, and `[null dataspace]` is HDF5's empty dataspace.

## R values and what R writes

The governing rule is that R writes what Python writes for the equivalent value.
The fixture case is the evidence for each row.

| R value | Equivalent Python value | Encoding | On-disk dtype | Fixture cases |
| ------- | ----------------------- | -------- | ------------- | ------------- |
| `double` vector, matrix or array | float64 ndarray | `array` 0.2.0 | float64 | `array_float64`, `array_float64_2d`, `array_float64_3d`, `array_float64_empty`, `array_float64_0x3`, `array_float64_special` |
| `integer` vector or matrix, no `NA` | int32 ndarray | `array` 0.2.0 | int32 | `array_int32`, `array_int32_2d` |
| `logical` array, no `NA` | bool ndarray | `array` 0.2.0 | h5py enum bool (int8) | `array_bool`, `array_bool_2d` |
| `complex` array | complex128 ndarray | `array` 0.2.0 | compound `r`/`i` of float64 | `array_complex128` |
| `character` vector, matrix or array | `U`/object ndarray | `string-array` 0.2.0 | variable-length UTF-8 | `string_array_1d`, `string_array_object`, `string_array_2d`, `string_array_empty` |
| Any of the above with length 1 and a `dim` (or `as_array()`) | 1-element ndarray | `array` or `string-array` | as above | `array_float64_1elem`, `string_array_1elem` |
| length-1 `double`, no `dim` | float | `numeric-scalar` 0.2.0 | float64, scalar dataspace | `scalar_python_float`, `scalar_float64` |
| length-1 `integer`, no `dim` | np.int32 | `numeric-scalar` 0.2.0 | int32, scalar dataspace | `scalar_int32` (Python `int` gives int64, `scalar_python_int`) |
| length-1 `logical`, no `dim` | bool | `numeric-scalar` 0.2.0 | bool, scalar dataspace | `scalar_python_bool`, `scalar_bool` |
| length-1 `complex`, no `dim` | complex | `numeric-scalar` 0.2.0 | complex128, scalar dataspace | `scalar_complex128` |
| length-1 `character`, no `dim` | str | `string` 0.2.0 | variable-length UTF-8, scalar dataspace | `scalar_python_str`, `scalar_str_empty` |
| `NULL` | None | `null` 0.1.0 | empty dataspace (float32 placeholder) | `null`, `dict_with_null` |
| named `list` | dict | `dict` 0.1.0 | group, no members when empty | `dict_nested`, `dict_empty`, `dict_with_null` |
| rec-array structure | structured ndarray | `rec-array` 0.2.0 | compound, see below | `rec_array_basic`, `rec_array_widths`, `rec_array_rank_genes_groups`, `rec_array_object_field` |
| `dgCMatrix`, `lgCMatrix` | csc_matrix | `csc_matrix` 0.1.0 | `data` float64 or bool, `indices`/`indptr` int32, attribute `shape` int64 pair | `csc_float64`, `csc_bool` |
| `dgRMatrix`, `lgRMatrix` | csr_matrix | `csr_matrix` 0.1.0 | as `csc_matrix` | `csr_float64`, `csr_bool`, `csr_empty`, `csr_0_rows` |
| `DataFrame` | DataFrame | `dataframe` 0.2.0 | group, see below | `df_all_types`, `df_two_columns`, `df_no_columns`, `df_no_rows_str_index` |
| `factor`, `ordered` | Categorical | `categorical` 0.2.0 | see below | `df_col_categorical`, `df_col_categorical_ordered`, `df_col_categorical_missing` |
| `integer` with `NA` | Int32 | `nullable-integer` 0.1.0 | `values` int32, `mask` bool | `df_col_nullable_int_nomissing`, `df_col_nullable_int` |
| `logical` with `NA` | boolean | `nullable-boolean` 0.1.0 | `values` bool, `mask` bool | `df_col_nullable_bool` |
| `character` with `NA` | str (NaN) | `nullable-string-array` 0.1.0 | `values` variable-length UTF-8, `mask` bool, attribute `na-value` | `df_col_str_na` |
| `AnnData` | AnnData | `anndata` 0.1.0 | group with `X` and the Slots | `anndata_full`, `anndata_no_raw`, `anndata_empty_slots`, `anndata_sparse_x`, `anndata_no_x`, `anndata_0_obs`, `anndata_0_vars` |
| `Raw` | Raw | `raw` 0.1.0 | group inside `anndata` | `anndata_full` |
| none (read only) | `bytes` | `bytes` 0.2.0 | fixed-length ASCII, scalar | `bytes_scalar` |

### Decisions

- **Scalar versus array** follows the spec: Python writes a numpy scalar or Python scalar as `numeric-scalar`/`string` and a 1-element ndarray as `array`/`string-array`, with identical values (`array_float64_1elem` against `scalar_float64`).
- **Sparse `data` dtype and index dtype** follow the in-memory dtype (`csr_float32`, `csr_int8`, `csr_int64`, `csc_float32`, `csc_int8`, `csc_int32`, `csc_int64`).
  The default index dtype is int32 (`csr_float64`) and is kept as the record says when it was int64 (`csr_indices_int64`).
  With `write_csr_csc_indices_with_min_possible_dtype` the **`indices`** (not `indptr`) shrink to the smallest unsigned dtype that holds the minor axis size (columns for csr, rows for csc, `methods.py:806-815`: at most 255 is `uint8`, then `uint16`, `uint32`, `uint64`), which was `uint8` for 4 columns (`csr_indices_min_dtype`, `csr_indices_int64_min_dtype`).
  `indptr` stays at its dtype.
  `csr_array` writes the same `csr_matrix` encoding (`csr_array_float64`).
- **int64 policy:** decided here. R integers are int32, so a read int64 or uint64 value is converted to `double` when every value has magnitude below 2^53.
  Otherwise the read raises a classed error naming the path, so `bit64` is not needed in Imports.
  Python `int` scalars are int64 on disk (`scalar_python_int`), so on-disk dtype records are what bring int64 back on write (the spike recommended `bit64conversion`, the decision is to use it only to check exactness and then convert).
- **NaN:** a double `NA_real_` and `NaN` both write as a float NaN (`array_float64_special`, `df_col_float64_nan`).
  Floats have no mask, so `NA` is not distinguishable on read.
- **Logical with and without `NA`:** without `NA` the bool `array` (`df_col_bool`), with `NA` a `nullable-boolean` group (`df_col_nullable_bool`).
  The same applies to `integer` (`df_col_int32` against `df_col_nullable_int`).
  Python writes the nullable form for any pandas nullable dtype, even with no missing value (`df_col_nullable_int_nomissing`), so a record of the encoding read from disk is needed to round trip it.
- **Nullable float** has no encoding: Python raises `IORegistryError` for `Float64` (`df_col_nullable_float`), so R never writes it.
- **Complex:** only `complex128` is written (`array_complex128`, `scalar_complex128`), and `complex64` (`array_complex64`) is read only as the spike recommends.

### Dataframes

- Every group has attributes `_index` (the name of the index dataset) and `column-order` (an array of the column names, `str`), in addition to the encoding attributes.
  An empty `column-order` is a float64 empty array (`df_no_columns`), which h5py writes for an empty list.
- The index is a dataset named `_index`, or the index name when it has one (`df_index_named`: the dataset is named `cell` and `_index='cell'`).
  Columns and the index never share a dataset name, if a column has the index name and the same values only one dataset is written (`df_index_same_as_column`).
- A string index (the AnnData case, `obs_names`/`var_names`) is a `nullable-string-array` with `na-value='NaN'`, with an all-`False` mask when nothing is missing.
  This is what pandas 3 gives, and `df_index_na`, `df_index_duplicates` and `df_index_nonascii` keep the values as given (a missing name is written as `''` under a `True` mask).
  `df_index_range` and `df_index_int` write a plain int64 `array` and `df_index_categorical` a `categorical`.
- **Column rules** (all columns share `dataframe` 0.2.0):
  - float32, float64, int8, int32, int64, uint8 and bool numpy columns are plain `array`s of the same dtype (`df_col_float32`, `df_col_float64`, `df_col_int8`, `df_col_int32`, `df_col_int64`, `df_col_uint8`, `df_col_bool`), and other widths are not observed
  - the pandas 3 default `str` column (what an R `character` column maps to) is a `nullable-string-array` with `na-value='NaN'`, even with no missing value (`df_col_str`, `df_col_str_na`)
  - the `string` dtype with `pd.NA` is a `nullable-string-array` with `na-value='NA'` (`df_col_string_pdna`)
  - nullable integer and boolean columns are `nullable-integer` and `nullable-boolean` groups with `values` of the integer width (`df_col_nullable_int8`, `df_col_nullable_uint16`, `df_col_nullable_int`)
  - categorical columns are `categorical` groups, see below
- **`allow_write_nullable_strings`:** with the default (`None`) and with `True` string columns are `nullable-string-array`s (`df_col_str_allow_nullable_true`).
  With `False` a column and the index without missing values are written as plain `string-array`s (`df_col_str_allow_nullable_false`, which also writes `_index` as a `string-array`), and a column with missing values raises `ValueError` (`df_col_str_na_allow_nullable_false`).
  R follows the default and does not expose the setting in this ticket.
- Column order is preserved by `column-order` only, the datasets are in alphabetical order in the group (`df_columns_order`).
- A 0-row frame writes empty datasets with the same encodings (`df_no_rows_str_index`, the R case).
  `df_no_rows` has an `object` index, which Python writes as a plain empty `string-array`.

### Categoricals

- A `categorical` group has attribute `ordered` (bool) and members `codes` and `categories`
- `categories` is a `string-array` for string levels, and keeps its dtype for others (`int64` for `df_col_categorical_numeric`, bool for `df_col_categorical_bool`).
  An R `factor` always has character levels.
- The code dtype is the smallest signed integer pandas picks for the number of categories `n`: int8 when `n < 127`, int16 when `n < 32767` and int32 otherwise (`df_col_categorical` n=3, `df_col_categorical_126` int8, `df_col_categorical_127` and `df_col_categorical_128` int16, `df_col_categorical_32767` and `df_col_categorical_32768` int32)
- A missing value is the code `-1` (`df_col_categorical_missing`) and unused categories are kept (`df_col_categorical_empty`)
- `ordered` is `True` for `ordered` factors (`df_col_categorical_ordered`)

### rec-array

- Fields keep their dtype: numeric widths, bool as an enum (`rec_array_widths`), and `S` fields stay fixed-length ASCII (`fixed:S3-ascii` in `rec_array_basic`)
- `U` and object fields are written as variable-length UTF-8 (`uni:vlen-utf-8`, `rec_array_object_field`), which is what scanpy's `rank_genes_groups` names need (`rec_array_rank_genes_groups`)
- Field order is the dtype order

### Whole objects

- All nine slot groups are always present (`anndata_empty_slots`: `layers`, `obsm`, `obsp`, `uns`, `varm` and `varp` are `dict` groups even when empty, `obs` and `var` are `dataframe`)
- `X` is a dataset or group at the root and is absent when there is none (`anndata_no_x`), and sparse X is a `csr_matrix` group (`anndata_sparse_x`)
- Zero observations or variables keep the empty dimension on `X` (`anndata_0_obs`, `anndata_0_vars`)
- `raw` is a `raw` group with `X`, `var` and `varm` (`anndata_full`, `anndata_no_raw`)

### Errors Python raises

- `Float64` nullable columns: `IORegistryError`
- `allow_write_nullable_strings = False` with a missing string: `ValueError`

Both are in the table's last rows, and are recorded in the fixtures manifest under `errors`.

## Observed table

<!-- observed:start -->
| Case | Python value | Encoding | On disk | Other attributes |
| ---- | ------------ | -------- | ------- | ---------------- |
| `anndata_0_obs` |  | anndata 0.1.0 | {X: array 0.2.0: float32 [0x3] = []; layers: dict 0.1.0; obs: dataframe 0.2.0; obsm: dict 0.1.0; obsp: dict 0.1.0; uns: dict 0.1.0; var: dataframe 0.2.0; varm: dict 0.1.0; varp: dict 0.1.0} |  |
| `anndata_0_vars` |  | anndata 0.1.0 | {X: array 0.2.0: float32 [2x0] = []; layers: dict 0.1.0; obs: dataframe 0.2.0; obsm: dict 0.1.0; obsp: dict 0.1.0; uns: dict 0.1.0; var: dataframe 0.2.0; varm: dict 0.1.0; varp: dict 0.1.0} |  |
| `anndata_empty_slots` |  | anndata 0.1.0 | {X: array 0.2.0: float32 [2x3] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]; layers: dict 0.1.0; obs: dataframe 0.2.0; obsm: dict 0.1.0; obsp: dict 0.1.0; uns: dict 0.1.0; var: dataframe 0.2.0; varm: dict 0.1.0; varp: dict 0.1.0} |  |
| `anndata_full` |  | anndata 0.1.0 | {X: array 0.2.0: float32 [4x3]; layers: dict 0.1.0; obs: dataframe 0.2.0; obsm: dict 0.1.0; obsp: dict 0.1.0; raw: raw 0.1.0; uns: dict 0.1.0; var: dataframe 0.2.0; varm: dict 0.1.0; varp: dict 0.1.0} |  |
| `anndata_no_raw` |  | anndata 0.1.0 | {X: array 0.2.0: float32 [4x3]; layers: dict 0.1.0; obs: dataframe 0.2.0; obsm: dict 0.1.0; obsp: dict 0.1.0; uns: dict 0.1.0; var: dataframe 0.2.0; varm: dict 0.1.0; varp: dict 0.1.0} |  |
| `anndata_no_x` |  | anndata 0.1.0 | {layers: dict 0.1.0; obs: dataframe 0.2.0; obsm: dict 0.1.0; obsp: dict 0.1.0; uns: dict 0.1.0; var: dataframe 0.2.0; varm: dict 0.1.0; varp: dict 0.1.0} |  |
| `anndata_sparse_x` |  | anndata 0.1.0 | {X: csr_matrix 0.1.0; layers: dict 0.1.0; obs: dataframe 0.2.0; obsm: dict 0.1.0; obsp: dict 0.1.0; uns: dict 0.1.0; var: dataframe 0.2.0; varm: dict 0.1.0; varp: dict 0.1.0} |  |
| `array_bool` | ndarray bool (3,) | array 0.2.0 | array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [True, False, True] |  |
| `array_bool_2d` | ndarray bool (2, 3) | array 0.2.0 | array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [2x3] = [True, False, True, False, False, True] |  |
| `array_complex128` | ndarray complex128 (2,) | array 0.2.0 | array 0.2.0: complex128 (compound r, i of 8-byte floats) [2] = [(1+2j), (-3.5+0.25j)] |  |
| `array_complex64` | ndarray complex64 (2,) | array 0.2.0 | array 0.2.0: complex64 (compound r, i of 4-byte floats) [2] = [(1+2j), (-3.5+0.25j)] |  |
| `array_float32` | ndarray float32 (3,) | array 0.2.0 | array 0.2.0: float32 [3] = [1.0, 2.0, 3.0] |  |
| `array_float64` | ndarray float64 (3,) | array 0.2.0 | array 0.2.0: float64 [3] = [1.0, 2.0, 3.0] |  |
| `array_float64_0x3` | ndarray float64 (0, 3) | array 0.2.0 | array 0.2.0: float64 [0x3] = [] |  |
| `array_float64_1elem` | ndarray float64 (1,) | array 0.2.0 | array 0.2.0: float64 [1] = [2.5] |  |
| `array_float64_2d` | ndarray float64 (2, 3) | array 0.2.0 | array 0.2.0: float64 [2x3] = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0] |  |
| `array_float64_3d` | ndarray float64 (2, 3, 4) | array 0.2.0 | array 0.2.0: float64 [2x3x4] |  |
| `array_float64_empty` | ndarray float64 (0,) | array 0.2.0 | array 0.2.0: float64 [0] = [] |  |
| `array_float64_special` | ndarray float64 (4,) | array 0.2.0 | array 0.2.0: float64 [4] = [1.5, -2.25, nan, inf] |  |
| `array_int16` | ndarray int16 (3,) | array 0.2.0 | array 0.2.0: int16 [3] = [1, 2, 3] |  |
| `array_int32` | ndarray int32 (3,) | array 0.2.0 | array 0.2.0: int32 [3] = [1, 2, 3] |  |
| `array_int32_2d` | ndarray int32 (2, 3) | array 0.2.0 | array 0.2.0: int32 [2x3] = [0, 1, 2, 3, 4, 5] |  |
| `array_int32_min` | ndarray int32 (3,) | array 0.2.0 | array 0.2.0: int32 [3] = [-2147483648, 0, 5] |  |
| `array_int64` | ndarray int64 (3,) | array 0.2.0 | array 0.2.0: int64 [3] = [1, 2, 3] |  |
| `array_int8` | ndarray int8 (3,) | array 0.2.0 | array 0.2.0: int8 [3] = [1, 2, 3] |  |
| `array_uint16` | ndarray uint16 (3,) | array 0.2.0 | array 0.2.0: uint16 [3] = [1, 2, 3] |  |
| `array_uint32` | ndarray uint32 (3,) | array 0.2.0 | array 0.2.0: uint32 [3] = [1, 2, 3] |  |
| `array_uint64` | ndarray uint64 (3,) | array 0.2.0 | array 0.2.0: uint64 [3] = [1, 2, 3] |  |
| `array_uint8` | ndarray uint8 (3,) | array 0.2.0 | array 0.2.0: uint8 [3] = [1, 2, 3] |  |
| `bytes_scalar` |  | bytes 0.2.0 | bytes 0.2.0: string(fixed 9, ascii) [scalar] = ['raw bytes'] |  |
| `categorical` | Categorical str | categorical 0.2.0 | {categories: string-array 0.2.0: string(variable, utf-8) [3] = ['c0', 'c1', 'c2']; codes: array 0.2.0: int8 [3] = [0, 1, 2]} | ordered=False (bool) |
| `categorical_126` | Categorical str | categorical 0.2.0 | {categories: string-array 0.2.0: string(variable, utf-8) [126]; codes: array 0.2.0: int8 [3] = [0, 1, 125]} | ordered=False (bool) |
| `categorical_127` | Categorical str | categorical 0.2.0 | {categories: string-array 0.2.0: string(variable, utf-8) [127]; codes: array 0.2.0: int16 [3] = [0, 1, 126]} | ordered=False (bool) |
| `categorical_32767` | Categorical str | categorical 0.2.0 | {categories: string-array 0.2.0: string(variable, utf-8) [32767]; codes: array 0.2.0: int32 [3] = [0, 1, 32766]} | ordered=False (bool) |
| `categorical_32768` | Categorical str | categorical 0.2.0 | {categories: string-array 0.2.0: string(variable, utf-8) [32768]; codes: array 0.2.0: int32 [3] = [0, 1, 32767]} | ordered=False (bool) |
| `categorical_bool` | Categorical bool | categorical 0.2.0 | {categories: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [2] = [False, True]; codes: array 0.2.0: int8 [3] = [1, 0, 1]} | ordered=False (bool) |
| `categorical_empty` | Categorical str | categorical 0.2.0 | {categories: string-array 0.2.0: string(variable, utf-8) [2] = ['a', 'b']; codes: array 0.2.0: int8 [0] = []} | ordered=False (bool) |
| `categorical_missing` | Categorical str | categorical 0.2.0 | {categories: string-array 0.2.0: string(variable, utf-8) [3] = ['c0', 'c1', 'c2']; codes: array 0.2.0: int8 [3] = [0, -1, 2]} | ordered=False (bool) |
| `categorical_nonascii` | Categorical str | categorical 0.2.0 | {categories: string-array 0.2.0: string(variable, utf-8) [2] = ['é', '日本']; codes: array 0.2.0: int8 [3] = [0, 1, 0]} | ordered=False (bool) |
| `categorical_numeric` | Categorical int64 | categorical 0.2.0 | {categories: array 0.2.0: int64 [3] = [0, 1, 2]; codes: array 0.2.0: int8 [3] = [0, 1, 2]} | ordered=False (bool) |
| `categorical_one_level` | Categorical str | categorical 0.2.0 | {categories: string-array 0.2.0: string(variable, utf-8) [1] = ['a']; codes: array 0.2.0: int8 [1] = [0]} | ordered=False (bool) |
| `categorical_ordered` | Categorical str | categorical 0.2.0 | {categories: string-array 0.2.0: string(variable, utf-8) [3] = ['c0', 'c1', 'c2']; codes: array 0.2.0: int8 [3] = [0, 1, 2]} | ordered=True (bool) |
| `categorical_unused` | Categorical str | categorical 0.2.0 | {categories: string-array 0.2.0: string(variable, utf-8) [3] = ['a', 'b', 'unused']; codes: array 0.2.0: int8 [3] = [0, 1, 0]} | ordered=False (bool) |
| `csc_bool` | csc_matrix bool, index int32 | csc_matrix 0.1.0 | {data: (none): bool (enum int8: FALSE=0, TRUE=1) [5] = [True, True, True, True, True]; indices: (none): int32 [5] = [1, 0, 2, 0, 2]; indptr: (none): int32 [5] = [0, 1, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csc_float32` | csc_matrix float32, index int32 | csc_matrix 0.1.0 | {data: (none): float32 [5] = [3.0, 1.0, 4.0, 2.0, 5.0]; indices: (none): int32 [5] = [1, 0, 2, 0, 2]; indptr: (none): int32 [5] = [0, 1, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csc_float64` | csc_matrix float64, index int32 | csc_matrix 0.1.0 | {data: (none): float64 [5] = [3.0, 1.0, 4.0, 2.0, 5.0]; indices: (none): int32 [5] = [1, 0, 2, 0, 2]; indptr: (none): int32 [5] = [0, 1, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csc_indices_int64` | csc_matrix float64, index int64 | csc_matrix 0.1.0 | {data: (none): float64 [5] = [3.0, 1.0, 4.0, 2.0, 5.0]; indices: (none): int64 [5] = [1, 0, 2, 0, 2]; indptr: (none): int64 [5] = [0, 1, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csc_indices_int64_min_dtype` | csc_matrix float64, index int64 | csc_matrix 0.1.0 | {data: (none): float64 [5] = [3.0, 1.0, 4.0, 2.0, 5.0]; indices: (none): uint8 [5] = [1, 0, 2, 0, 2]; indptr: (none): int64 [5] = [0, 1, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csc_indices_min_dtype` | csc_matrix float64, index int32 | csc_matrix 0.1.0 | {data: (none): float64 [5] = [3.0, 1.0, 4.0, 2.0, 5.0]; indices: (none): uint8 [5] = [1, 0, 2, 0, 2]; indptr: (none): int32 [5] = [0, 1, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csc_int16` | csc_matrix int16, index int32 | csc_matrix 0.1.0 | {data: (none): int16 [5] = [3, 1, 4, 2, 5]; indices: (none): int32 [5] = [1, 0, 2, 0, 2]; indptr: (none): int32 [5] = [0, 1, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csc_int32` | csc_matrix int32, index int32 | csc_matrix 0.1.0 | {data: (none): int32 [5] = [3, 1, 4, 2, 5]; indices: (none): int32 [5] = [1, 0, 2, 0, 2]; indptr: (none): int32 [5] = [0, 1, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csc_int64` | csc_matrix int64, index int32 | csc_matrix 0.1.0 | {data: (none): int64 [5] = [3, 1, 4, 2, 5]; indices: (none): int32 [5] = [1, 0, 2, 0, 2]; indptr: (none): int32 [5] = [0, 1, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csc_int8` | csc_matrix int8, index int32 | csc_matrix 0.1.0 | {data: (none): int8 [5] = [3, 1, 4, 2, 5]; indices: (none): int32 [5] = [1, 0, 2, 0, 2]; indptr: (none): int32 [5] = [0, 1, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csc_uint16` | csc_matrix uint16, index int32 | csc_matrix 0.1.0 | {data: (none): uint16 [5] = [3, 1, 4, 2, 5]; indices: (none): int32 [5] = [1, 0, 2, 0, 2]; indptr: (none): int32 [5] = [0, 1, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csc_uint32` | csc_matrix uint32, index int32 | csc_matrix 0.1.0 | {data: (none): uint32 [5] = [3, 1, 4, 2, 5]; indices: (none): int32 [5] = [1, 0, 2, 0, 2]; indptr: (none): int32 [5] = [0, 1, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csc_uint64` | csc_matrix uint64, index int32 | csc_matrix 0.1.0 | {data: (none): uint64 [5] = [3, 1, 4, 2, 5]; indices: (none): int32 [5] = [1, 0, 2, 0, 2]; indptr: (none): int32 [5] = [0, 1, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csc_uint8` | csc_matrix uint8, index int32 | csc_matrix 0.1.0 | {data: (none): uint8 [5] = [3, 1, 4, 2, 5]; indices: (none): int32 [5] = [1, 0, 2, 0, 2]; indptr: (none): int32 [5] = [0, 1, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csc_wide` | csc_matrix float64, index int32 | csc_matrix 0.1.0 | {data: (none): float64 [3] = [1.0, 2.0, 3.0]; indices: (none): int32 [3] = [0, 299, 150]; indptr: (none): int32 [3] = [0, 2, 3]} | shape=[300, 2] (int64) |
| `csc_wide_min_dtype` | csc_matrix float64, index int32 | csc_matrix 0.1.0 | {data: (none): float64 [3] = [1.0, 2.0, 3.0]; indices: (none): uint16 [3] = [0, 299, 150]; indptr: (none): int32 [3] = [0, 2, 3]} | shape=[300, 2] (int64) |
| `csr_0_rows` | csr_matrix float64, index int32 | csr_matrix 0.1.0 | {data: (none): float64 [0] = []; indices: (none): int32 [0] = []; indptr: (none): int32 [1] = [0]} | shape=[0, 4] (int64) |
| `csr_array_float64` | csr_array float64, index int32 | csr_matrix 0.1.0 | {data: (none): float64 [5] = [1.0, 2.0, 3.0, 4.0, 5.0]; indices: (none): int32 [5] = [1, 3, 0, 2, 3]; indptr: (none): int32 [4] = [0, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csr_bool` | csr_matrix bool, index int32 | csr_matrix 0.1.0 | {data: (none): bool (enum int8: FALSE=0, TRUE=1) [5] = [True, True, True, True, True]; indices: (none): int32 [5] = [1, 3, 0, 2, 3]; indptr: (none): int32 [4] = [0, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csr_empty` | csr_matrix float64, index int32 | csr_matrix 0.1.0 | {data: (none): float64 [0] = []; indices: (none): int32 [0] = []; indptr: (none): int32 [4] = [0, 0, 0, 0]} | shape=[3, 4] (int64) |
| `csr_float32` | csr_matrix float32, index int32 | csr_matrix 0.1.0 | {data: (none): float32 [5] = [1.0, 2.0, 3.0, 4.0, 5.0]; indices: (none): int32 [5] = [1, 3, 0, 2, 3]; indptr: (none): int32 [4] = [0, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csr_float64` | csr_matrix float64, index int32 | csr_matrix 0.1.0 | {data: (none): float64 [5] = [1.0, 2.0, 3.0, 4.0, 5.0]; indices: (none): int32 [5] = [1, 3, 0, 2, 3]; indptr: (none): int32 [4] = [0, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csr_indices_int64` | csr_matrix float64, index int64 | csr_matrix 0.1.0 | {data: (none): float64 [5] = [1.0, 2.0, 3.0, 4.0, 5.0]; indices: (none): int64 [5] = [1, 3, 0, 2, 3]; indptr: (none): int64 [4] = [0, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csr_indices_int64_min_dtype` | csr_matrix float64, index int64 | csr_matrix 0.1.0 | {data: (none): float64 [5] = [1.0, 2.0, 3.0, 4.0, 5.0]; indices: (none): uint8 [5] = [1, 3, 0, 2, 3]; indptr: (none): int64 [4] = [0, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csr_indices_min_dtype` | csr_matrix float64, index int32 | csr_matrix 0.1.0 | {data: (none): float64 [5] = [1.0, 2.0, 3.0, 4.0, 5.0]; indices: (none): uint8 [5] = [1, 3, 0, 2, 3]; indptr: (none): int32 [4] = [0, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csr_int16` | csr_matrix int16, index int32 | csr_matrix 0.1.0 | {data: (none): int16 [5] = [1, 2, 3, 4, 5]; indices: (none): int32 [5] = [1, 3, 0, 2, 3]; indptr: (none): int32 [4] = [0, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csr_int32` | csr_matrix int32, index int32 | csr_matrix 0.1.0 | {data: (none): int32 [5] = [1, 2, 3, 4, 5]; indices: (none): int32 [5] = [1, 3, 0, 2, 3]; indptr: (none): int32 [4] = [0, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csr_int64` | csr_matrix int64, index int32 | csr_matrix 0.1.0 | {data: (none): int64 [5] = [1, 2, 3, 4, 5]; indices: (none): int32 [5] = [1, 3, 0, 2, 3]; indptr: (none): int32 [4] = [0, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csr_int8` | csr_matrix int8, index int32 | csr_matrix 0.1.0 | {data: (none): int8 [5] = [1, 2, 3, 4, 5]; indices: (none): int32 [5] = [1, 3, 0, 2, 3]; indptr: (none): int32 [4] = [0, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csr_uint16` | csr_matrix uint16, index int32 | csr_matrix 0.1.0 | {data: (none): uint16 [5] = [1, 2, 3, 4, 5]; indices: (none): int32 [5] = [1, 3, 0, 2, 3]; indptr: (none): int32 [4] = [0, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csr_uint32` | csr_matrix uint32, index int32 | csr_matrix 0.1.0 | {data: (none): uint32 [5] = [1, 2, 3, 4, 5]; indices: (none): int32 [5] = [1, 3, 0, 2, 3]; indptr: (none): int32 [4] = [0, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csr_uint64` | csr_matrix uint64, index int32 | csr_matrix 0.1.0 | {data: (none): uint64 [5] = [1, 2, 3, 4, 5]; indices: (none): int32 [5] = [1, 3, 0, 2, 3]; indptr: (none): int32 [4] = [0, 2, 3, 5]} | shape=[3, 4] (int64) |
| `csr_uint8` | csr_matrix uint8, index int32 | csr_matrix 0.1.0 | {data: (none): uint8 [5] = [1, 2, 3, 4, 5]; indices: (none): int32 [5] = [1, 3, 0, 2, 3]; indptr: (none): int32 [4] = [0, 2, 3, 5]} | shape=[3, 4] (int64) |
| `df_all_types` | DataFrame[f:float64, i:int32, b:bool, s:str, cat:category, ni:Int64] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; b: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [True, False, True]; cat: categorical 0.2.0 (ordered=False (bool)) {categories: string-array 0.2.0: string(variable, utf-8) [3] = ['c0', 'c1', 'c2']; codes: array 0.2.0: int8 [3] = [0, 1, 2]}; f: array 0.2.0: float64 [3] = [1.5, 2.5, 3.5]; i: array 0.2.0: int32 [3] = [1, 2, 3]; ni: nullable-integer 0.1.0 {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, True, False]; values: array 0.2.0: int64 [3] = [1, 0, 3]}; s: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['a', 'b', 'c']}} | _index='_index' (str); column-order=['f', 'i', 'b', 's', 'cat', 'ni'] (str) |
| `df_col_bool` | DataFrame[c:bool] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, True, True]} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_categorical` | DataFrame[c:category] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: categorical 0.2.0 (ordered=False (bool)) {categories: string-array 0.2.0: string(variable, utf-8) [3] = ['c0', 'c1', 'c2']; codes: array 0.2.0: int8 [3] = [0, 1, 2]}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_categorical_126` | DataFrame[c:category] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: categorical 0.2.0 (ordered=False (bool)) {categories: string-array 0.2.0: string(variable, utf-8) [126]; codes: array 0.2.0: int8 [3] = [0, 1, 125]}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_categorical_127` | DataFrame[c:category] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: categorical 0.2.0 (ordered=False (bool)) {categories: string-array 0.2.0: string(variable, utf-8) [127]; codes: array 0.2.0: int16 [3] = [0, 1, 126]}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_categorical_128` | DataFrame[c:category] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: categorical 0.2.0 (ordered=False (bool)) {categories: string-array 0.2.0: string(variable, utf-8) [128]; codes: array 0.2.0: int16 [3] = [0, 1, 127]}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_categorical_32767` | DataFrame[c:category] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: categorical 0.2.0 (ordered=False (bool)) {categories: string-array 0.2.0: string(variable, utf-8) [32767]; codes: array 0.2.0: int32 [3] = [0, 1, 32766]}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_categorical_32768` | DataFrame[c:category] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: categorical 0.2.0 (ordered=False (bool)) {categories: string-array 0.2.0: string(variable, utf-8) [32768]; codes: array 0.2.0: int32 [3] = [0, 1, 32767]}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_categorical_bool` | DataFrame[c:category] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: categorical 0.2.0 (ordered=False (bool)) {categories: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [2] = [False, True]; codes: array 0.2.0: int8 [3] = [1, 0, 1]}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_categorical_empty` | DataFrame[c:category] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: categorical 0.2.0 (ordered=False (bool)) {categories: string-array 0.2.0: string(variable, utf-8) [3] = ['a', 'b', 'unused']; codes: array 0.2.0: int8 [3] = [0, 1, 0]}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_categorical_missing` | DataFrame[c:category] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: categorical 0.2.0 (ordered=False (bool)) {categories: string-array 0.2.0: string(variable, utf-8) [3] = ['c0', 'c1', 'c2']; codes: array 0.2.0: int8 [3] = [0, -1, 2]}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_categorical_numeric` | DataFrame[c:category] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: categorical 0.2.0 (ordered=False (bool)) {categories: array 0.2.0: int64 [3] = [0, 1, 2]; codes: array 0.2.0: int8 [3] = [0, 1, 2]}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_categorical_ordered` | DataFrame[c:category] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: categorical 0.2.0 (ordered=True (bool)) {categories: string-array 0.2.0: string(variable, utf-8) [3] = ['c0', 'c1', 'c2']; codes: array 0.2.0: int8 [3] = [0, 1, 2]}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_float32` | DataFrame[c:float32] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: array 0.2.0: float32 [3] = [0.0, 1.0, 1.0]} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_float64` | DataFrame[c:float64] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: array 0.2.0: float64 [3] = [0.0, 1.0, 1.0]} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_float64_nan` | DataFrame[c:float64] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: array 0.2.0: float64 [3] = [1.5, nan, inf]} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_int32` | DataFrame[c:int32] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: array 0.2.0: int32 [3] = [0, 1, 1]} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_int64` | DataFrame[c:int64] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: array 0.2.0: int64 [3] = [0, 1, 1]} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_int8` | DataFrame[c:int8] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: array 0.2.0: int8 [3] = [0, 1, 1]} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_nullable_bool` | DataFrame[c:boolean] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: nullable-boolean 0.1.0 {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, True, False]; values: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [True, False, False]}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_nullable_int` | DataFrame[c:Int64] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: nullable-integer 0.1.0 {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, True, False]; values: array 0.2.0: int64 [3] = [1, 0, 3]}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_nullable_int8` | DataFrame[c:Int8] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: nullable-integer 0.1.0 {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, True, False]; values: array 0.2.0: int8 [3] = [1, 0, 3]}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_nullable_int_nomissing` | DataFrame[c:Int32] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: nullable-integer 0.1.0 {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: array 0.2.0: int32 [3] = [1, 2, 3]}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_nullable_uint16` | DataFrame[c:UInt16] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: nullable-integer 0.1.0 {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, True, False]; values: array 0.2.0: uint16 [3] = [1, 0, 3]}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_object_str` | DataFrame[c:str] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['a', 'b', 'c']}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_str` | DataFrame[c:str] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['a', 'bé', '']}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_str_allow_nullable_false` | DataFrame[c:str] index str | dataframe 0.2.0 | {_index: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']; c: string-array 0.2.0: string(variable, utf-8) [3] = ['a', 'bé', '']} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_str_allow_nullable_true` | DataFrame[c:str] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['a', 'bé', '']}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_str_na` | DataFrame[c:str] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, True, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['a', '', '']}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_str_na_allow_nullable_true` | DataFrame[c:str] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, True, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['a', '', '']}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_string_pdna` | DataFrame[c:string] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: nullable-string-array 0.1.0 (na-value='NA' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, True, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['a', '', 'c']}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_string_pdna_allow_nullable_true` | DataFrame[c:string] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: nullable-string-array 0.1.0 (na-value='NA' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, True, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['a', '', 'c']}} | _index='_index' (str); column-order=['c'] (str) |
| `df_col_uint8` | DataFrame[c:uint8] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; c: array 0.2.0: uint8 [3] = [0, 1, 1]} | _index='_index' (str); column-order=['c'] (str) |
| `df_columns_order` | DataFrame[z:int64, a:int64, m:int64] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; a: array 0.2.0: int64 [3] = [0, 1, 2]; m: array 0.2.0: int64 [3] = [0, 1, 2]; z: array 0.2.0: int64 [3] = [0, 1, 2]} | _index='_index' (str); column-order=['z', 'a', 'm'] (str) |
| `df_index_categorical` | DataFrame[c:float64] index category | dataframe 0.2.0 | {_index: categorical 0.2.0 (ordered=False (bool)) {categories: string-array 0.2.0: string(variable, utf-8) [2] = ['a', 'b']; codes: array 0.2.0: int8 [3] = [0, 1, 0]}; c: array 0.2.0: float64 [3] = [1.0, 2.0, 3.0]} | _index='_index' (str); column-order=['c'] (str) |
| `df_index_duplicates` | DataFrame[c:float64] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['a', 'a', 'b']}; c: array 0.2.0: float64 [3] = [1.0, 2.0, 3.0]} | _index='_index' (str); column-order=['c'] (str) |
| `df_index_int` | DataFrame[c:float64] index int64 | dataframe 0.2.0 | {_index: array 0.2.0: int64 [3] = [10, 20, 30]; c: array 0.2.0: float64 [3] = [1.0, 2.0, 3.0]} | _index='_index' (str); column-order=['c'] (str) |
| `df_index_na` | DataFrame[c:float64] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, True, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['a', '', 'b']}; c: array 0.2.0: float64 [3] = [1.0, 2.0, 3.0]} | _index='_index' (str); column-order=['c'] (str) |
| `df_index_named` | DataFrame[c:float64] index str | dataframe 0.2.0 | {c: array 0.2.0: float64 [3] = [1.0, 2.0, 3.0]; cell: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}} | _index='cell' (str); column-order=['c'] (str) |
| `df_index_nonascii` | DataFrame[c:float64] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['é', '日本', 'ß']}; c: array 0.2.0: float64 [3] = [1.0, 2.0, 3.0]} | _index='_index' (str); column-order=['c'] (str) |
| `df_index_range` | DataFrame[c:float64] index int64 | dataframe 0.2.0 | {_index: array 0.2.0: int64 [3] = [0, 1, 2]; c: array 0.2.0: float64 [3] = [1.0, 2.0, 3.0]} | _index='_index' (str); column-order=['c'] (str) |
| `df_index_same_as_column` | DataFrame[id:str] index str | dataframe 0.2.0 | {id: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['a', 'b', 'c']}} | _index='id' (str); column-order=['id'] (str) |
| `df_no_columns` | DataFrame[] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [2] = [False, False]; values: string-array 0.2.0: string(variable, utf-8) [2] = ['a', 'b']}} | _index='_index' (str); column-order=[] (float64) |
| `df_no_rows` | DataFrame[c:float64] index object | dataframe 0.2.0 | {_index: string-array 0.2.0: string(variable, utf-8) [0] = []; c: array 0.2.0: float64 [0] = []} | _index='_index' (str); column-order=['c'] (str) |
| `df_no_rows_str_index` | DataFrame[c:float64, s:str] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [0] = []; values: string-array 0.2.0: string(variable, utf-8) [0] = []}; c: array 0.2.0: float64 [0] = []; s: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [0] = []; values: string-array 0.2.0: string(variable, utf-8) [0] = []}} | _index='_index' (str); column-order=['c', 's'] (str) |
| `df_two_columns` | DataFrame[b:float64, a:int64] index str | dataframe 0.2.0 | {_index: nullable-string-array 0.1.0 (na-value='NaN' (str)) {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['r0', 'r1', 'r2']}; a: array 0.2.0: int64 [3] = [1, 2, 3]; b: array 0.2.0: float64 [3] = [1.0, 2.0, 3.0]} | _index='_index' (str); column-order=['b', 'a'] (str) |
| `dict_empty` | dict | dict 0.1.0 | {} |  |
| `dict_nested` | dict | dict 0.1.0 | {a: array 0.2.0: float64 [2] = [1.0, 2.0]; n: numeric-scalar 0.2.0: int64 [scalar] = [3]; s: string 0.2.0: string(variable, utf-8) [scalar] = ['str']; sub: dict 0.1.0 {flag: numeric-scalar 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [scalar] = [True]; names: string-array 0.2.0: string(variable, utf-8) [2] = ['x', 'y']}} |  |
| `dict_with_null` | dict | dict 0.1.0 | {nothing: null 0.1.0: float32 [null dataspace]; x: numeric-scalar 0.2.0: float64 [scalar] = [1.0]} |  |
| `null` | None | null 0.1.0 | null 0.1.0: float32 [null dataspace] |  |
| `nullable_bool` | BooleanArray | nullable-boolean 0.1.0 | {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, True, False]; values: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [True, False, False]} |  |
| `nullable_bool_nomissing` | BooleanArray | nullable-boolean 0.1.0 | {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [2] = [False, False]; values: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [2] = [True, False]} |  |
| `nullable_int32_nomissing` | IntegerArray | nullable-integer 0.1.0 | {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: array 0.2.0: int32 [3] = [1, 2, 3]} |  |
| `nullable_int64` | IntegerArray | nullable-integer 0.1.0 | {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, True, False]; values: array 0.2.0: int64 [3] = [1, 0, 3]} |  |
| `nullable_int8` | IntegerArray | nullable-integer 0.1.0 | {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, True, False]; values: array 0.2.0: int8 [3] = [1, 0, 3]} |  |
| `nullable_int_empty` | IntegerArray | nullable-integer 0.1.0 | {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [0] = []; values: array 0.2.0: int32 [0] = []} |  |
| `nullable_str` | StringArray | nullable-string-array 0.1.0 | {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [4] = [False, True, False, False]; values: string-array 0.2.0: string(variable, utf-8) [4] = ['a', '', 'bé', '']} | na-value='NaN' (str) |
| `nullable_str_allow_nullable_false` | StringArray | string-array 0.2.0 | string-array 0.2.0: string(variable, utf-8) [3] = ['a', 'bé', ''] |  |
| `nullable_str_nomissing` | StringArray | nullable-string-array 0.1.0 | {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, False, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['a', 'bé', '']} | na-value='NaN' (str) |
| `nullable_str_pdna` | StringArray | nullable-string-array 0.1.0 | {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, True, False]; values: string-array 0.2.0: string(variable, utf-8) [3] = ['a', '', '日本']} | na-value='NA' (str) |
| `nullable_uint16` | IntegerArray | nullable-integer 0.1.0 | {mask: array 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [3] = [False, True, False]; values: array 0.2.0: uint16 [3] = [1, 0, 3]} |  |
| `rec_array_basic` | structured ndarray [i:int32, f:float64, fixed:\|S3, uni:<U3] | rec-array 0.2.0 | rec-array 0.2.0: compound(i:int32, f:float64, fixed:S3-ascii, uni:vlen-utf-8) [2] |  |
| `rec_array_object_field` | structured ndarray [o:object, f:float64] | rec-array 0.2.0 | rec-array 0.2.0: compound(o:vlen-utf-8, f:float64) [2] |  |
| `rec_array_rank_genes_groups` | structured ndarray [0:<U2, 1:<U2] | rec-array 0.2.0 | rec-array 0.2.0: compound(0:vlen-utf-8, 1:vlen-utf-8) [2] |  |
| `rec_array_widths` | structured ndarray [u1:uint8, i2:int16, u4:uint32, i8:int64, f4:float32, b:bool] | rec-array 0.2.0 | rec-array 0.2.0: compound(u1:uint8, i2:int16, u4:uint32, i8:int64, f4:float32, b:bool) [2] |  |
| `scalar_bool` | np.bool scalar | numeric-scalar 0.2.0 | numeric-scalar 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [scalar] = [True] |  |
| `scalar_complex128` | np.complex128 scalar | numeric-scalar 0.2.0 | numeric-scalar 0.2.0: complex128 (compound r, i of 8-byte floats) [scalar] = [(1+2j)] |  |
| `scalar_float32` | np.float32 scalar | numeric-scalar 0.2.0 | numeric-scalar 0.2.0: float32 [scalar] = [1.0] |  |
| `scalar_float64` | np.float64 scalar | numeric-scalar 0.2.0 | numeric-scalar 0.2.0: float64 [scalar] = [1.0] |  |
| `scalar_int16` | np.int16 scalar | numeric-scalar 0.2.0 | numeric-scalar 0.2.0: int16 [scalar] = [1] |  |
| `scalar_int32` | np.int32 scalar | numeric-scalar 0.2.0 | numeric-scalar 0.2.0: int32 [scalar] = [1] |  |
| `scalar_int32_min` | np.int32 scalar | numeric-scalar 0.2.0 | numeric-scalar 0.2.0: int32 [scalar] = [-2147483648] |  |
| `scalar_int64` | np.int64 scalar | numeric-scalar 0.2.0 | numeric-scalar 0.2.0: int64 [scalar] = [1] |  |
| `scalar_int8` | np.int8 scalar | numeric-scalar 0.2.0 | numeric-scalar 0.2.0: int8 [scalar] = [1] |  |
| `scalar_python_bool` | bool | numeric-scalar 0.2.0 | numeric-scalar 0.2.0: bool (enum int8: FALSE=0, TRUE=1) [scalar] = [True] |  |
| `scalar_python_float` | float | numeric-scalar 0.2.0 | numeric-scalar 0.2.0: float64 [scalar] = [2.5] |  |
| `scalar_python_int` | int | numeric-scalar 0.2.0 | numeric-scalar 0.2.0: int64 [scalar] = [7] |  |
| `scalar_python_str` | str | string 0.2.0 | string 0.2.0: string(variable, utf-8) [scalar] = ['héllo'] |  |
| `scalar_str_empty` | str | string 0.2.0 | string 0.2.0: string(variable, utf-8) [scalar] = [''] |  |
| `scalar_uint16` | np.uint16 scalar | numeric-scalar 0.2.0 | numeric-scalar 0.2.0: uint16 [scalar] = [1] |  |
| `scalar_uint32` | np.uint32 scalar | numeric-scalar 0.2.0 | numeric-scalar 0.2.0: uint32 [scalar] = [1] |  |
| `scalar_uint64` | np.uint64 scalar | numeric-scalar 0.2.0 | numeric-scalar 0.2.0: uint64 [scalar] = [1] |  |
| `scalar_uint8` | np.uint8 scalar | numeric-scalar 0.2.0 | numeric-scalar 0.2.0: uint8 [scalar] = [1] |  |
| `string_array_1d` | ndarray <U2 (4,) | string-array 0.2.0 | string-array 0.2.0: string(variable, utf-8) [4] = ['a', 'bé', '', '日本'] |  |
| `string_array_1elem` | ndarray <U1 (1,) | string-array 0.2.0 | string-array 0.2.0: string(variable, utf-8) [1] = ['a'] |  |
| `string_array_2d` | ndarray <U1 (2, 3) | string-array 0.2.0 | string-array 0.2.0: string(variable, utf-8) [2x3] = ['a', 'b', 'c', 'd', 'e', 'f'] |  |
| `string_array_empty` | ndarray object (0,) | string-array 0.2.0 | string-array 0.2.0: string(variable, utf-8) [0] = [] |  |
| `string_array_object` | ndarray object (4,) | string-array 0.2.0 | string-array 0.2.0: string(variable, utf-8) [4] = ['a', 'bé', '', '日本'] |  |
| `df_col_nullable_float` |  | Python error | IORegistryError | No method registered for writing <class 'pandas.arrays.FloatingArray'> into <class 'h5py._hl.group.Group'> |
| `df_col_str_na_allow_nullable_false` |  | Python error | ValueError | Cannot write `pd.arrays.[Arrow]StringArray` with missing values when `anndata.settings.allow_write_nullable_strings` is set to False. Opt-in to writing these arrays by toggling it to True or remove missing values. |
| `nullable_str_na_allow_nullable_false` |  | Python error | ValueError | Cannot write `pd.arrays.[Arrow]StringArray` with missing values when `anndata.settings.allow_write_nullable_strings` is set to False. Opt-in to writing these arrays by toggling it to True or remove missing values. |
<!-- observed:end -->
