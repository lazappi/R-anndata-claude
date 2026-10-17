# Lazy seeds spike

Findings of lazy/01.
Status: complete, every item and candidate has a verdict.
Versions tested: DelayedArray 0.39.6, SparseArray 1.13.2, HDF5Array 1.41.3 (with h5mread), ZarrArray 1.1.7 (Bioconductor 3.24, installed for this spike) on Rarr 2.1.48 (devel), S4Vectors 0.51.9.
Python reference: anndata 0.13.4 (zarr 3.4.1).

Evidence:

- Files written by Python from `.ralph/oracle/make_lazy.py` (git-ignored): `a.h5ad`, `a_v3.zarr` (Python default, sharded and consolidated), `a_v2.zarr`, `b_chunked.*` (explicit 10x10 chunks) and `big.h5ad`/`big_v3.zarr` (int64 `-2^62` and uint64 `2^63+5`)
- `a` holds dense layers of every dtype (int8 to uint64, float32, float64, bool), CSR and CSC layers (float32, float64, int32, int64, uint8, bool) and an `obs` with categorical, nullable int, nullable boolean and nullable string columns
- Truth is `read_h5ad()` of `a.h5ad`
- Probe scripts (git-ignored): `probe-seeds.R` (HDF5Array), `probe-zarr.R` and `probe-zarr-big.R` (ZarrArray), `probe-own.R` (own seed), `probe-df.R` (DataFrame columns)

Verdicts: **pass**, **gap** (cannot do it) or **workaround** (does it with a caveat we can handle).

## HDF5Array generic seeds on h5ad

| Item | `HDF5ArraySeed` (dense) | `H5SparseMatrixSeed` (CSR/CSC) |
| ---- | ----------------------- | ------------------------------ |
| Values, full and random-access block (repeated and unsorted indices) | pass for int8 to uint64, float32, float64 | pass for float32, float64, int32, int64, uint8 |
| Orientation | workaround: the seed is the HDF5 view of the array, so `dim` is `var x obs` and it needs `t()` (lazy and cheap) | workaround: same |
| bool (h5py enum) | **gap**: `h5mread() does not support this type` | **gap**: the seed fails validation |
| Result type | workaround: types are R's (`raw` for uint8, `integer` for uint16, `double` for uint32/int64/uint64) and carry no On-disk dtype record, so `read_h5ad()` dtype records cannot be reproduced | same |
| int64 and uint64 at or above 2^53 | **gap**: read silently as doubles with lost precision, where `read_h5ad()` raises an error for values of magnitude 2^53 or more | same |
| Sparse results stay sparse | n/a | pass: `is_sparse()` is `TRUE` and `extract_sparse_array()` gives an `SVT_SparseMatrix` |
| Chunk grid | workaround: `chunkdim()` is the HDF5 chunk shape reversed, and `NULL` for the contiguous datasets Python writes by default, so a grid has to be chosen by us (`b_chunked` gave 10x10 reversed correctly) | n/a, no chunk grid |
| Nullable columns (`values` plus `mask` groups) | **gap** as a unit (we must combine two seeds), and the `mask` and bool `values` datasets are enums so they fail as above | n/a |
| Strings | pass for `obs/cat/categories` (character). The nullable string column is a group (`values` plus `mask`) and was not read through a seed | n/a |
| Dependencies | HDF5Array, h5mread, rhdf5 (already in Imports) | same |
| Consistency with backed classes | gap: a second reader of the same files with different dtype rules | same |

Extra `H5SparseMatrixSeed` probes (`probe-hsp.R`, `bigsp.h5ad`):

| Item | Verdict |
| ---- | ------- |
| int64 data at 2^62 | **gap**: read silently as the double 4.611686e18 where `read_h5ad()` raises the 2^53 error |
| Result types | workaround: uint8 gives `raw` (no On-disk dtype record, and `format()` and arithmetic fail on it), int16 and small uint32 give `integer`, int64 gives `double`. The type depends on the stored dtype, so uint32 values of 2^31 or more were not probed (they cannot be `integer`) |

HDF5Array does not read zarr.
`H5ADMatrix` was not used (ADR 0001).

## ZarrArray on zarr

| Item | Verdict |
| ---- | ------- |
| Works with Rarr devel, Python-default v3 (sharded, consolidated) and v2 stores | pass: dense layers of every dtype read correctly in both, and `ZarrArray()` takes the array directory |
| Values, full and block reads (repeated and unsorted indices) | pass for every dtype including bool (`logical`) |
| 64-bit and uint32 values | **gap**: `int64`, `uint64` and `uint32` arrays are typed `integer`, values beyond the integer range become `NA` with one warning per value (hundreds of warnings for a 50x30 array), so large arrays would take minutes. This is the Rarr behaviour that `zarr_split_read()` works around |
| Sparse groups (`csr_matrix`/`csc_matrix`) | **gap**: `ZarrArray()` fails with `isSingleString(base_type) is not TRUE`, as expected. Sparse bool is moot: it fails the same way as every sparse group (only the `data`, `indices` and `indptr` arrays could be opened one by one, as bool `logical` arrays) |
| Nullable columns | gap as a unit, the `values` and `mask` arrays read separately (pass for each) |
| Strings and categories | pass: `obs/cat/categories`, `obs/str/values` read as character |
| Chunk grid | pass: `chunkdim()` is the zarr chunk shape (`10x10` for `b_chunked`), for a small array in a Python-default store it is the whole array (`50x30`) |
| Dtype records | gap: no record of the On-disk dtype (uint8 is `integer`, not `raw`) |
| Dependencies | ZarrArray (Bioconductor devel, not on CRAN or a release branch matching our R) on top of Rarr >= 2.1.9 |

## Own seeds on the store layer

A minimal S4 seed (`extract_array()` calling `array_read()` with the sorted unique indices, then rearranging for repeated and unsorted indices in memory) was written in `probe-own.R`.

| Item | Verdict |
| ---- | ------- |
| h5ad dense, full and block (repeated, unsorted) | pass for every dtype (`probe-own2.R`) |
| zarr v3 and v2 dense, full and block | pass for every dtype after a fix in the store layer, see the next row |
| Cause of the earlier zarr block-read error | found and fixed: `as.integer(sort(unique(i)))` returns an ALTREP sorted wrapper, and Rarr's C `is_compact()` takes any ALTREP integer for a compact range, so `c(3L, 9L)` was read as `3:9` and Rarr's result positions (`1:7`) overran the output (`subscript out of bounds`). Plain vectors (and `c(3L, 9L)` typed in) were fine, which is why direct calls passed. `zarr_selection_index()` now makes selections plain with `+ 0L` (regression test in `test-io-store-zarr.R`). h5ad was never affected |
| dtype and values like `read_h5ad()`/`read_zarr()` | pass: for int8 to uint64, float32, float64 and bool on h5ad, zarr v3 and v2 the full and block values equal `read_h5ad()` and a selection read carries the same dtype record (`int8`, `uint32`, `float32` and so on, none for int32, float64 and bool) |
| R type of a selection | workaround: a small h5ad selection of int64, uint32 or uint64 returns `integer` where the whole read and zarr return `double`, so a seed must fix its `type()` from the dtype (not from a probe read) |
| 2^53 error | pass: reading int64 or uint64 values of magnitude 2^53 or more raises the same `Cannot read ... 2^53` error as `read_h5ad()`, for h5ad and zarr v3 (zarr v2 was not probed, it shares the read path with v3, and the big fixture was written for v3 only. It is raised by the read that touches them, so a seed raises on realising, not on construction) |
| bool, nullable and string columns | pass: `array_read()` of `obs/nint/values` (int64 record) and `mask`, `obs/nbool/values` and `mask` (logical), `obs/cat/codes` (int8 record), `obs/cat/categories` and `obs/str/values` (character, subset by selection) for h5ad, v3 and v2. Only the group itself (`obs/str`, a nullable string array) has no array read, a column class combines the parts |
| Sparse | pass: `indptr` read whole, then `data` and `indices` slices by `array_read()`, with dtype records (`float32`, `int64`, `uint8`, none for bool) identical on h5ad, v3 and v2. `R/backed-sparse.R` already does this for h5ad, and the same code serves a seed on all three |
| Chunk grid | workaround: the store layer has no chunk shape operation, so one must be added (and `array_info()` has no backend-neutral `shape`: h5 gives `dim` reversed as text, zarr gives nothing, `zarr_array_meta()$shape` is internal). The pieces exist as internals (`zarr_chunk_shape()`, `guess_chunk()`, `h5_info()`, `zarr_info()`) |
| Dependencies | none beyond DelayedArray and SparseArray |
| Consistency with backed | pass: one code path for backed and lazy, and both formats |
| Cost | most work: S4 seed classes, shape and chunk operations, tests per dtype |

## `S4Vectors::DataFrame` with DelayedArray columns (lazy `obs`/`var`)

Tested with `HDF5Array` columns and a toy `LazyFactor` S4 class (a 1-d DelayedArray of codes plus levels).

| Item | Verdict |
| ---- | ------- |
| Construction and `nrow` | pass: columns stay `HDF5Array`/`DelayedArray` |
| Row subsetting (`df[c(3, 1, 3), ]`), column subsetting, logical subsetting | pass: columns stay lazy (`DelayedArray`), values are right |
| Printing | pass: shows `<DelayedArray>` as the column type and realises only the shown rows |
| Realising | pass: `as.data.frame(df)` gives numeric columns |
| `cbind`, `df$new <- col * 2`, arithmetic | pass: stays lazy |
| Lazy factor-like class | pass for subsetting and printing once `length()`, `[` and `show()` are defined (`[` must use `drop = FALSE` for 1-d arrays). It fails to realise in `as.data.frame()` until an `as.data.frame()` (or `as.vector()`) method is defined, so that method is part of the class |
| Nullable columns | same approach: a small class holding `values` and `mask` |

## Recommendation

- **Seeds**: build our own seeds on the store layer and the backed classes, for dense and sparse, h5ad and zarr
  - Neither HDF5Array nor ZarrArray carries the On-disk dtype records, so reading through them would differ from `read_h5ad()` and `read_zarr()` in dtype and in the 2^53 error.
    Both fail on bool, HDF5Array has no zarr, ZarrArray has no sparse groups and produces floods of warnings and `NA` for 64-bit values.
  - One code path serves backed, lazy, h5ad and zarr
  - Needed first: a backend-neutral `array_info()` `shape` and chunk shape, and a seed `type()` fixed from the dtype (the zarr block read error is fixed, see above)
  - HDF5Array's `H5SparseMatrixSeed` is the best off-the-shelf piece (sparse stays sparse) but it fails for bool, returns `raw` for uint8 and reads 2^53 or larger int64 silently, so it is not worth a dependency
- **Lazy `obs`/`var`**: an `S4Vectors::DataFrame` with 1-d DelayedArray columns plus small S4 classes for categorical (codes seed plus categories) and nullable (values plus mask) columns, each defining `length`, `[`, `show` and `as.vector`/`as.data.frame` realisation
- **Imports**: DelayedArray and SparseArray (as the spec says), no HDF5Array or ZarrArray
- **Open for the checkpoint**: whether to accept the cost of own seeds against the lower effort of `HDF5ArraySeed` for dense h5ad numeric data only (it would need a second path for bool, nullable and zarr, so it is not recommended)
