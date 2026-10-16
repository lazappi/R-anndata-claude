# zarr library spike

Findings of zarr-io/01, re-run against development versions (human decision, 2026-10-16).
Candidates tested:

- `Rarr` 2.1.48 (Bioconductor devel, `Huber-group-EMBL/Rarr@devel`)
- `zarr` 0.5.1.9000 (GitHub main, `R-CF/zarr`)
- `pizzarr` 0.2.1 (CRAN), kept from the first run for comparison

`pizzarr` main (0.2.2) was **not tested**: it fails at configure without a Rust toolchain (`rustc` >= 1.91 and OpenSSL), which is too heavy a requirement for source installs.
`blosc` 0.1.2 (CRAN) is a codec package, not a zarr library.
No other zarr library was found on CRAN or Bioconductor.
Python reference: zarr 3.4.1 with anndata 0.13.4 (`tests/python/uv.lock`).

Evidence:

- Fixtures from `tests/python/zarr_spike_fixtures.py` (v2 and v3 stores of every dtype, codec and layout, plus a zip store and an anndata-written store)
- Probe scripts in `.scratch/zarr-io/spike/`, which print one line per array: `probe-read.R` (Rarr, zarr, pizzarr reading), `probe-write.R` (zarr and pizzarr writing), `probe-write-rarr-devel.R`, `probe-rarr-dtypes.R` and `probe-rarr-misc.R` (Rarr devel)
- `tests/python/zarr_describe.py` shows what Python reads from a store R wrote
- Regenerate the stores the probes read with `uv run --project tests/python python -I tests/python/zarr_spike_fixtures.py .scratch/zarr-io/spike/out` (not committed)
- Package tests for the recommended library are `tests/testthat/test-zarr-spike.R`, each marked with its verdict

Verdicts: **pass**, **gap** (cannot do it) or **workaround** (does it with a caveat we can handle).

## Release results (first run, short note)

The first run used the release versions: Rarr 1.10.1 (reads v2 only, no groups, no v3 at all, so rejected), zarr 0.5.1 and pizzarr 0.2.1.
pizzarr was then the recommendation, with gaps in v3 strings, v3 scalars, sharding, empty v2 strings and consolidated writing.
The development version of Rarr closes most of them, so the tables below are for the development versions.

## Recommendation

Use **Rarr** (development version, `Rarr (>= 2.1.48)` in Imports with `Remotes: Huber-group-EMBL/Rarr@devel` until it is released).
It is the only candidate that reads every anndata dtype and layout correctly in v2 and v3 (including v3 strings, scalars and sharded arrays), writes groups and arrays in both formats, reads consolidated metadata and writes it.
It needs no codec package (blosc, zstd and gzip are built in), has no system library beyond GNU make and has an MIT licence like pizzarr.
It is designed for slices (`index =`), which `backed` and `lazy` need.

The write side has gaps that need code of our own (a thin writer layer on top of Rarr, not a fallback to our own zarr implementation):

1. **Strings are written as fixed-width bytes** (`|S<n>` in v2, `null_terminated_bytes` in v3) for both formats, and non-ASCII text is cut to the declared byte width (the width is the character count, so multi-byte characters are mangled).
   anndata writes variable-length strings (v2 `vlen-utf8`, v3 `string`).
   `data_type = "|O"` errors and leaves a broken `zarr.json`.
   We need a string writer: the vlen-utf8 chunk format is simple (4-byte count header, then 4-byte little-endian length and UTF-8 bytes per item) and the metadata is a small JSON document, so write the metadata and chunk files for string arrays ourselves, or `create_empty_zarr_array()` for the metadata and our own chunk bytes.
   Python writes v3 strings as `data_type` `string` with codecs `vlen-utf8` then `zstd` (level 0, no checksum), and v2 strings as dtype `|O` with the `vlen-utf8` filter and a blosc compressor (read from the fixture metadata).
2. **0-dimensional arrays cannot be written** (`'dims' cannot be of length 0`).
   They read back as length-1 arrays (`dim()` is 1), so the on-disk shape must come from the metadata.
   Scalars (`numeric-scalar`, `string`) need our own writer for the metadata and the single chunk.
3. **The integer data type defaults to the smallest that fits** (`matrix(0:5)` is written as `uint8`), so the writer must always pass `data_type`.
4. **int64 and uint64 cannot be written from doubles** (`REAL() can only be applied to a 'numeric'`), only from R integers.
   Values beyond 2^31 need `bit64` or a double route (not needed for anndata indices of realistic size, but needed for large `indptr`).
5. **Bool `NA` becomes `FALSE`** (with a warning): anndata nullable booleans use the mask encoding, so this is only a caveat.
6. **Writing shards** is not supported (`write_zarr_array()` has no shard argument).
   Python's `settings.auto_shard_zarr_v3` defaults to `True` (`_settings.py:57`), so anndata-written v3 stores are sharded by default.
   Reading is covered, and for writing the human should decide whether R-written v3 stores may be unsharded (a structural difference, still readable by Python) or whether writing shards is in scope (needs our own shard writer with a crc32c index).
7. **Zip stores** are not supported: a `.zarr.zip` is treated as a directory.
   `utils::unzip()` to a temporary directory is a possible read-only workaround, writing a zip needs `zip` or our own code.
8. **Reading 64-bit integers** gives R integers, so values beyond 2^31 are lost or error (anndata never gets near this in `indices`, `indptr` may for huge matrices: check when the sparse encodings are built).
9. Group and array attribute arrays come back as lists (`unlist()`), objects as named lists.

Codecs Python writes by default (observed in the fixture metadata from zarr 3.4.1): v3 is `bytes` (little-endian) then `zstd` (level 0, no checksum), and sharded arrays wrap those in `sharding_indexed` with a `crc32c` index.
v2 is blosc (`cname` lz4, shuffle) for numeric arrays and `vlen-utf8` for strings.
Rarr reads all of these.

Codec packages: **none needed**.
The open problem from the first run (pizzarr could not find the `blosc` package under `R CMD check`) was only that `blosc` was not declared in `DESCRIPTION`, and under `--as-cran` the tests only see declared packages.
It does not apply to Rarr, which has its own blosc support.
If `blosc` were ever needed it would go in Suggests (GPL (>= 3) with a `libblosc` system library) with a classed error naming the package.

## Store abstraction

Yes, the h5ad element registry should gain a backend-neutral store abstraction, but the decision is left to the agents as the spec says.
Recommended shape, based on how the encodings use HDF5 today:

- A small internal interface: `read_node_attrs(store, path)`, `write_node_attrs(store, path, attrs)`, `read_array(store, path, selection)` and `write_array(store, path, value, ...)`, plus `list_children(store, path)`, `create_group(store, path)` and `node_type(store, path)`.
- The H5 implementation wraps the existing `read_dataset()`, `write_dataset()` and attribute helpers, so h5ad behaviour is unchanged.
- The zarr implementation wraps Rarr plus the write gaps above (strings, scalars, dtypes) and is where the zarr-specific encoding differences (scalar strings, `methods.py:1395-1420`) live.
- Encodings call the interface, never rhdf5 or Rarr directly.
  This refactor touches every `R/io-*.R` file and should be a ticket of its own before the first zarr encoding.

Mapping to R:

- `dim()` equals the on-disk (C-order) shape, and `x[i, j]` is numpy's `x[i, j]`.
  This is the same convention as rhdf5 with `native = TRUE`.
- A 0-d array reads with `dim()` 1 (length 1), so the shape must come from metadata when it matters.
- Missing chunks read as the array's `fill_value` for integers, floats (including a NaN fill value) and bools.

## Verdicts

Notation: the cell has v2 and v3 where they differ.

### Rarr 2.1.48 (devel, recommended)

| Item | Verdict | Notes |
|---|---|---|
| Read v2 / v3 | pass / pass | Every integer, float, bool, string and scalar fixture |
| Write v2 / v3 | workaround / workaround | Groups, nested groups, numeric and bool arrays, attributes, all read back by Python. Gaps are strings, 0-d arrays, 64-bit from doubles and the default integer type (see the recommendation) |
| Sharding (v3) | pass (read) / gap (write) | Sharded fixture reads, `write_zarr_array()` has no shard argument |
| Consolidated metadata | pass | `read_zarr_consolidated_metadata()` reads `.zmetadata` and v3 inline metadata, `zarr_consolidate_metadata()` writes both and Python opens them |
| Integer dtypes | workaround | int8 to uint64 read as R integers (no 64-bit loss within the integer range). Writes narrow to the smallest type unless `data_type` is given |
| Floats and bool | pass | NaN, Inf, NaN fill value. Bool `NA` is written as `FALSE` with a warning |
| Strings | workaround | Reads v2 `vlen-utf8` and the v3 string type, empty strings and non-ASCII intact. Writes fixed-width bytes (truncates non-ASCII) |
| 0-d arrays | workaround | Reads (length-1 array), cannot write |
| Default codecs | pass | zstd, blosc, gzip and uncompressed read (v2 and v3), zstd, blosc and others write, no `blosc` package needed |
| Attributes | pass | Group and array, read and write, arrays as lists and objects as named lists |
| Partial reads | pass | `read_zarr_array(path, index = list(...))` reads only the needed chunks |
| Zip store | gap | Local, HTTP and S3 stores only |
| Shape mapping, fill values | pass | `dim()` is the on-disk shape, missing chunks use the fill value |
| Maintenance | pass | Bioconductor, active (devel 2.1.48), by Huber group (EMBL) |
| Dependencies, licence | pass | Imports `curl`, `grumpy`, `jsonlite`, `paws.storage`, `R.utils`, `rlang`, `utils`, no system libraries beyond GNU make, MIT |

### zarr 0.5.1.9000 (main)

| Item | Verdict | Notes |
|---|---|---|
| Read v2 / v3 | gap / workaround | v2 reads give `NA` for the value 0 and wrong values for int64 and uint32 and uint64. v3 reads work for floats, bool and strings |
| Write v2 / v3 | gap / gap | v3 only. Output has invalid metadata (a `null` string fill value, so Python cannot list the group), bool cannot be written (`boolean` is not a valid type) and int64 is rejected |
| Sharding (v3) | pass (read) | Sharded fixture reads, v2 sharded fails (not applicable). Not tested for write |
| Consolidated metadata | gap | No function in the package for reading or writing consolidated metadata |
| Integer dtypes | gap | The fill value 0 reads as `NA`, int64, uint32 and uint64 return wrong values |
| Floats and bool | workaround | Read correctly in v3, but a value equal to the fill value becomes `NA`, which silently corrupts sparse `indptr`/`indices` |
| Strings | pass / gap | v3 reads, v2 fails on write |
| 0-d arrays | workaround | Reads, but int is bit64 garbage |
| Default codecs | pass | zstd, blosc, gzip and sharding read in v3 |
| Attributes | pass | Read |
| Partial reads | workaround | `read(selection)` exists, not exercised because the package fails on the basics above |
| Zip store | gap | Local, memory, HTTP and S3 stores |
| Shape mapping, fill values | gap | `dim()` is the on-disk shape, but the fill value always becomes `NA` (see integer dtypes) |
| Maintenance | pass | Active, one maintainer |
| Dependencies, licence | workaround | `Rcpp`, `blosc` (system library `libblosc`), MIT |

Rejected: the fill value to `NA` mapping alone breaks anndata (zero is a valid value in sparse data), and writing produces invalid stores.
The development version fixes none of the problems found in 0.5.1.

### pizzarr 0.2.1 (CRAN release, kept for comparison)

| Item | Verdict | Notes |
|---|---|---|
| Read v2 / v3 | pass / pass | Numeric, bool arrays |
| Write v2 / v3 | pass / pass | Numeric and bool arrays, groups, attrs |
| Sharding (v3) | gap | No `sharding_indexed` codec |
| Consolidated metadata | workaround | Opens and reads Python stores, no writing |
| Integer dtypes | workaround | int8-16, uint8-32 as R integer, int64 as `integer64`, uint64 as `integer64` with a warning above 2^63 |
| Floats and bool | pass | NaN and Inf survive, a v2 float `NaN` fill value arrives as the string `"NaN"` |
| Strings | workaround / gap | v2 reads, but empty strings read as `"\005"`. v3: error |
| 0-d arrays | workaround / gap | v2 numeric only, v3 read fails and v3 write stores 0 |
| Default codecs | workaround | blosc needs the `blosc` package (GPL, system library) |
| Attributes | pass | Group and array, arrays come back as lists |
| Partial reads | pass | `get_item(list(slice(a, b), ...))` reads only the chunks needed |
| Zip store | gap | Directory, memory, HTTP, S3 and GCS stores only |
| Shape mapping, fill values | pass | `dim()` is the on-disk shape, missing chunks use `fill_value` |
| Maintenance | pass | Released 2026-08, zarr-developers organisation |
| Dependencies, licence | pass | Pure R, MIT (0.2.2 needs a Rust toolchain) |

pizzarr main (0.2.2) was not tested because it needs a Rust toolchain.
Compared with Rarr devel it has more gaps on the read side and fewer on the write side for 64-bit and bool, and it has the same string and scalar write gaps.

## Not tested

- Remote stores (out of scope per the spec)
- Reading the anndata-written stores (`anndata.zarr`) end to end: that is the job of the first encoding tickets
- Sharded **writes** (no candidate supports them)
- pizzarr main (needs Rust)
