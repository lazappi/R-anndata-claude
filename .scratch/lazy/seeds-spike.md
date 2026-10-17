# Lazy seeds spike

Findings of lazy/01.
Status: draft, the own-seed verdicts for zarr and several probes are still open (see the ticket and `fix_plan.md`).
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

HDF5Array does not read zarr.
`H5ADMatrix` was not used (ADR 0001).

## ZarrArray on zarr

| Item | Verdict |
| ---- | ------- |
| Works with Rarr devel, Python-default v3 (sharded, consolidated) and v2 stores | pass: dense layers of every dtype read correctly in both, and `ZarrArray()` takes the array directory |
| Values, full and block reads (repeated and unsorted indices) | pass for every dtype including bool (`logical`) |
| 64-bit and uint32 values | **gap**: `int64`, `uint64` and `uint32` arrays are typed `integer`, values beyond the integer range become `NA` with one warning per value (hundreds of warnings for a 50x30 array), so large arrays would take minutes. This is the Rarr behaviour that `zarr_split_read()` works around |
| Sparse groups (`csr_matrix`/`csc_matrix`) | **gap**: `ZarrArray()` fails with `isSingleString(base_type) is not TRUE`, as expected |
| Nullable columns | gap as a unit, the `values` and `mask` arrays read separately (pass for each) |
| Strings and categories | pass: `obs/cat/categories`, `obs/str/values` read as character |
| Chunk grid | pass: `chunkdim()` is the zarr chunk shape (`10x10` for `b_chunked`), for a small array in a Python-default store it is the whole array (`50x30`) |
| Dtype records | gap: no record of the On-disk dtype (uint8 is `integer`, not `raw`) |
| Dependencies | ZarrArray (Bioconductor devel, not on CRAN or a release branch matching our R) on top of Rarr >= 2.1.9 |

## Own seeds on the store layer

A minimal S4 seed (`extract_array()` calling `array_read()` with the sorted unique indices, then rearranging for repeated and unsorted indices in memory) was written in `probe-own.R`.

| Item | Verdict |
| ---- | ------- |
| h5ad dense, full and block (repeated, unsorted) | pass for `d_int32` |
| zarr v3 dense | **unresolved**: the full read passed but the block read raised `subscript out of bounds` from `Rarr::read_zarr_array()` inside the seed, while the same selections (`list(c(3L, 9L), c(1L, 7L))` and others) succeed when `array_read()` is called directly, with or without DelayedArray loaded. The cause was not found in the five attempts allowed. A real implementation must find it (it may be the selection list DelayedArray hands over, or the empty `0 x 0` calls it makes first) |
| zarr v2 | not reached because of the above |
| dtype and values like `read_h5ad()`/`read_zarr()` | by construction pass, as the store layer already applies the dtype records, the 64-bit rules (the error at 2^53) and the bool and nullable handling |
| Sparse | pass in principle: `R/backed-sparse.R` already reads `indptr`, then `data` and `indices` slices, for h5ad (the backed classes), and the same code can serve a seed. A zarr version needs `array_read()` only |
| Chunk grid | workaround: the store layer has no chunk shape operation, so one must be added (and `array_info()` has no backend-neutral `shape`, h5 gives `dim` reversed as text and zarr gives nothing, `zarr_array_meta()$shape` is internal) |
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
  - Needed first: a backend-neutral `array_info()` `shape` and chunk shape, and the zarr block read error above
  - HDF5Array's `H5SparseMatrixSeed` is the best off-the-shelf piece (sparse stays sparse) but it fails for bool and copies the dtype problem, so it is not worth a dependency
- **Lazy `obs`/`var`**: an `S4Vectors::DataFrame` with 1-d DelayedArray columns plus small S4 classes for categorical (codes seed plus categories) and nullable (values plus mask) columns, each defining `length`, `[`, `show` and `as.vector`/`as.data.frame` realisation
- **Imports**: DelayedArray and SparseArray (as the spec says), no HDF5Array or ZarrArray
- **Open for the checkpoint**: whether to accept the cost of own seeds against the lower effort of `HDF5ArraySeed` for dense h5ad numeric data only (it would need a second path for bool, nullable and zarr, so it is not recommended)
