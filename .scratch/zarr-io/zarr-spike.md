# zarr library spike

Findings of zarr-io/01.
Candidates tested: `Rarr` 1.10.1 (Bioconductor), `pizzarr` 0.2.1 (CRAN), `zarr` 0.5.1 (CRAN) and `blosc` 0.1.2 (CRAN, a codec package, not a zarr library).
No other zarr library was found on CRAN or Bioconductor.
Python reference: zarr 3.4.1 with anndata 0.13.4 (`tests/python/uv.lock`).

Evidence:

- Fixtures from `tests/python/zarr_spike_fixtures.py` (v2 and v3 stores of every dtype, codec and layout, plus a zip store and an anndata-written store)
- Probe scripts in `.scratch/zarr-io/spike/` (`probe-read.R`, `probe-write.R`, `probe-pizzarr.R`), which print one line per array and can be rerun against the regenerated stores
- `tests/python/zarr_describe.py` shows what Python reads from a store R wrote
- Regenerate the stores the probes read with `uv run --project tests/python python -I tests/python/zarr_spike_fixtures.py .scratch/zarr-io/spike/out` (not committed)
- Package tests for the recommended library were written as `tests/testthat/test-zarr-spike.R` and are set aside in the git stash `zarr-io/01: pizzarr verdict tests (fail under R CMD check, blosc)`, see the open problem below
- The `DESCRIPTION` Imports entry for `pizzarr` is provisional until the human accepts the recommendation

Verdicts: **pass**, **gap** (cannot do it) or **workaround** (does it with a caveat we can handle).

## Recommendation

Use **pizzarr**, with small wrappers around its gaps, in the order of the fallback list in the spec (step 1).
It is the only candidate that reads v2 and v3 correctly, writes both and has the codecs anndata uses.
The gaps are real though, and two of them (v3 strings and sharding) need code of our own below the pizzarr API, so the human checkpoint should decide whether that is acceptable or whether to go to step 2 (our own R implementation of the zarr subset, reusing pizzarr's codecs).

Gaps to fill, in priority order:

1. **v3 variable-length strings** (read and write): pizzarr has no `string` data type or `vlen-utf8` codec in its v3 pipeline.
   The vlen-utf8 byte format is simple (4-byte little-endian length then UTF-8 bytes, per item, with a 4-byte count header), so the fix is a codec registered into pizzarr's internal `CODEC_CONSTRUCTORS` plus a data type mapping (internal, so pinned to the tested pizzarr version) or a wrapper that reads and writes the chunk bytes of string arrays itself.
2. **0-dimensional arrays in v3** (read) and **v3 scalar writing** (writes `0` instead of the value): wrap by reading/writing the single chunk file.
   v2 numeric scalars work, v2 string scalars fail on read.
3. **Sharding** (v3, read and write): no `sharding_indexed` codec.
   Reading a shard is an index lookup (crc32c-checked) plus the inner codecs, which pizzarr already has, so a sharding codec is feasible.
   Writing shards (`auto_shard_zarr_v3`) is the larger part.
   Needs a crc32c implementation (small, in R or C).
4. **Consolidated metadata writing**: pizzarr opens consolidated stores (it ignores the extra metadata) but cannot write `.zmetadata` or v3 inline consolidated metadata.
   Both are JSON documents assembled from the node metadata, which a wrapper can do.
5. **Zip stores**: not supported (a `.zarr.zip` is treated as a directory).
   Out of scope until a store abstraction exists, `utils::unzip()` to a temporary directory is a possible read-only workaround.
6. **uint64**: values reach R as bit64 `integer64`, which is signed, so pizzarr warns above 2^63.
   anndata never gets near that, so convert after reading and ignore.
7. **v2 empty strings** read as `"\005"`, which corrupts missing values in string columns.
   This and gap 1 together mean we will probably own string decoding (and encoding) for both versions, which is the strongest argument for the human to consider fallback step 2.
8. **v2 float `NaN` fill value** arrives as the string `"NaN"`: convert in the wrapper.

Codecs Python writes by default (observed in the fixture metadata from zarr 3.4.1): v3 is `bytes` (little-endian) then `zstd` (level 0, no checksum), and sharded arrays wrap those in `sharding_indexed` with a `crc32c` index.
v2 is blosc (`cname` lz4, shuffle) for numeric arrays and `vlen-utf8` for strings.

Codec packages: **`blosc` is needed**.
pizzarr has its own gzip, zlib, bz2, lzma and zstd codecs (its Imports are `jsonlite`, `R6`, `qs2`, `stringr`, `memoise`, `stats`, `utils`, with `bit64` for int64), but its Blosc codec calls the CRAN `blosc` package (a Suggests of pizzarr).
Python's v2 default compressor is blosc (lz4), so every Python-written v2 store needs it, and v3 stores written with blosc do too.
`blosc` (GPL (>= 3), needs `libblosc`, which the macOS and Windows binaries bundle) would have to be added to Imports or Suggests.
The GPL-3 licence would constrain the package licence (BSD-3) if it is in Imports.

**Open problem (needs a human)**: with `blosc` installed in the user library, a blosc-compressed store reads in `devtools::test()` / `scripts/check.sh --quick`, but under the full `R CMD check` pizzarr fails with `blosc package must be installed to use the Blosc codec` (`.libPaths()` is the same and `requireNamespace("blosc")` is TRUE in a separate session).
The cause was not found in 5 attempts, so the package test file was set aside (git stash `zarr-io/01: pizzarr verdict tests`).
Candidates: `blosc` fails to load only in the check environment (for example its shared library), or pizzarr tests availability in a way that differs there.

Add to `DESCRIPTION` Imports: `pizzarr` (done in this ticket).

## Store abstraction

Yes, the h5ad element registry should gain a backend-neutral store abstraction, but the decision is left to the agents as the spec says.
Recommended shape, based on how the encodings use HDF5 today:

- A small internal interface of four verbs: `read_node_attrs(store, path)`, `write_node_attrs(store, path, attrs)`, `read_array(store, path, selection)` and `write_array(store, path, value, ...)`, plus `list_children(store, path)`, `create_group(store, path)` and `node_type(store, path)`.
- The H5 implementation wraps the existing `read_dataset()`, `write_dataset()` and attribute helpers, so h5ad behaviour is unchanged.
- The zarr implementation wraps pizzarr plus the gap wrappers above, and is where the zarr-specific encoding differences (scalar strings, `methods.py:1395-1420`) live.
- Encodings call the interface, never rhdf5 or pizzarr directly.
  This refactor touches every `R/io-*.R` file and should be a ticket of its own before the first zarr encoding.

Mapping to R:

- `dim()` equals the on-disk (C-order) shape, and `x[i, j]` is numpy's `x[i, j]` (pizzarr reads the chunk data transposed into column-major so no manual permutation is needed).
  This is the same convention as rhdf5 with `native = TRUE`.
- A 0-d array has `shape` `integer(0)`.
- Missing chunks read as the array's `fill_value` for integers, floats (v3) and bools.

## Verdicts

Notation: the cell has v2 and v3 where they differ.

### pizzarr 0.2.1 (recommended)

| Item | Verdict | Notes |
|---|---|---|
| Read v2 / v3 | pass / pass | Every integer, float and bool array in the fixtures |
| Write v2 / v3 | pass / pass | Numeric and bool arrays, groups, attrs, read back by Python. Group and array metadata correct |
| Sharding (v3) | gap | `Unsupported V3 codec: 'sharding_indexed'` on read, no write |
| Consolidated metadata | workaround | Python-written stores open and read. No writing in v2 or v3 |
| Integer dtypes | workaround | int8-16, uint8-32 as R integer, int64 as `integer64`, uint64 as `integer64` with a warning above 2^63 |
| Floats and bool | pass | NaN and Inf survive. v2 float `NaN` fill value becomes the string `"NaN"` |
| Strings | workaround / gap | v2 `vlen-utf8` reads and writes, but an empty string reads back as `"\005"` (wrapper must repair it, or read string chunks ourselves). v3 `string` type: error on read and write |
| 0-d arrays | workaround / gap | v2 numeric reads, v2 string fails, v3 read fails (`'dims' cannot be of length 0`), v3 write stores 0 |
| Default codecs | workaround | zstd, blosc, gzip, uncompressed read (v2, v3) and zstd, blosc write, but blosc needs the `blosc` package (open problem above) |
| Attributes | pass | Group and array, arrays come back as lists (`unlist()`), objects as named lists |
| Partial reads | pass | `get_item(list(slice(a, b), ...))` reads only the chunks needed |
| Zip store | gap | Directory, memory, HTTP, S3 and GCS stores only |
| Shape mapping, fill values | pass | See above, missing chunks use `fill_value` |
| Maintenance | pass | Released 2026-08, maintainer David Blodgett (USGS), part of the zarr-developers organisation |
| Dependencies, licence | pass | Pure R, no system libraries, MIT |

### zarr 0.5.1

| Item | Verdict | Notes |
|---|---|---|
| Read v2 / v3 | gap / workaround | v2 reads give `NA` for every value and fail for strings. v3 reads work for floats, bool, strings and chunks |
| Write v2 / v3 | gap / gap | v3 only (the array builder requires format 3). v3 output has wrong values for a matrix with `NA` and invalid metadata for 1-d arrays (`chunk_shape` written as a number), so Python fails to open the group |
| Sharding (v3) | pass (read) | Sharded fixture reads. Not tested for write |
| Consolidated metadata | gap | No function in the package exports for reading or writing `.zmetadata` or inline v3 consolidated metadata (the Python-written fixtures still open, the extra metadata is ignored) |
| Integer dtypes | gap | int8 to int32 read with the fill value `0` turned into `NA`, int64 and uint64 return wrong values (raw bits), uint32 errors |
| Floats and bool | workaround | Read correctly in v3, but a value equal to the fill value (default 0) becomes `NA`, which silently corrupts sparse `indptr`/`indices`. Bool cannot be written (`boolean` is not valid) |
| Strings | pass / gap | v3 reads, v2 fails. v3 writes (not verified against Python, the group did not open) |
| 0-d arrays | workaround | Reads (not for int, which is bit64 garbage), writes |
| Default codecs | pass | zstd, blosc, gzip and sharding read in v3. Needs the suggested `zlib` and `qs2` packages |
| Attributes | pass | Read |
| Partial reads | workaround | `read(selection)` takes a selection, not exercised because the package fails on the basics above |
| Zip store | gap | Local, memory, HTTP and S3 stores |
| Shape mapping, fill values | gap | `dim()` correct, but the fill value always becomes `NA` and data is stored in R order with a transpose codec by default |
| Maintenance | pass | Released 2026-09, active, one maintainer |
| Dependencies, licence | workaround | `Rcpp`, `blosc` (system library `libblosc`), MIT |

Rejected: the fill value to `NA` mapping alone breaks anndata (zero is a valid value in sparse data), and v2 and 1-d writing do not work.

### Rarr 1.10.1

| Item | Verdict | Notes |
|---|---|---|
| Read v2 / v3 | pass / gap | v3 gives `Reading Zarr v3 arrays is not currently supported` |
| Write v2 / v3 | workaround / gap | v2 arrays only, no groups (no `.zgroup` written, so Python cannot open the store as a group), no v3 argument |
| Sharding (v3) | gap | |
| Consolidated metadata | pass (read) | Reads `.zmetadata` of Python stores, no write |
| Integer dtypes | pass | All widths read as R integer (values above the integer range would be lost) |
| Floats and bool | workaround | Floats pass, bool reads, `Currently only able to write integer, double, and character arrays` |
| Strings | gap | Reads v2 `vlen-utf8`. Writes fixed-width bytes (`\|S2`), so non-ASCII text is truncated |
| 0-d arrays | gap | `'dims' cannot be of length 0` on read, a scalar writes as shape 1 |
| Default codecs | pass | zstd, blosc, gzip read, writes zlib, blosc, zstd and others |
| Attributes | workaround | `write_zarr_attributes()` exists, array-valued and object attributes read as lists |
| Partial reads | pass | Designed for it (`DelayedArray`) |
| Zip store | gap | Local, HTTP and S3 |
| Shape mapping, fill values | pass | `dim()` is the on-disk shape, missing chunks use the fill value |
| Maintenance | pass | Bioconductor, active (1.10.1, 2025-11) |
| Dependencies, licence | workaround | Depends on `DelayedArray` and `BiocGenerics`, Imports `paws.storage`, `curl`, `R.utils`, MIT |

Rejected: v2 only, arrays only and no scalars, so it cannot be the library even with wrappers.

### blosc 0.1.2

Not a zarr library.
A blosc codec (`libblosc` system library, GPL (>= 3)) used by `zarr`.
Needed by pizzarr's Blosc codec, see the recommendation above.
GPL-3 would constrain the package licence (BSD-3) if it is in Imports.

## Not tested

- Remote stores (out of scope per the spec)
- Reading the anndata-written stores (`anndata.zarr`) end to end: that is the job of the first encoding tickets
- Sharded **writes** and v3 consolidated metadata writes: they need our own code whichever library is chosen, since no candidate has them
