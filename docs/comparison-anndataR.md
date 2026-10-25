# anndata.claude compared with anndataR

Compared on 2026-10-24: anndata.claude 0.0.6.9000 (this repository) against anndataR 1.3.3 (commit `e09ad87`, `~/Documents/Code/scverse/anndataR`).
The comparison is mainly from reading the code.
Claims marked **(run)** were checked by running both packages (loaded with `pkgload::load_all()`) and Python anndata 0.13.4 from `tests/python`, on R 4.6.1, rhdf5 2.57.20 and Rarr 2.1.48 on macOS (x86_64).
Open anndataR issues were listed with `gh issue list -R scverse/anndataR` on the same day.

## Summary

The two packages start from different goals.

- **anndataR** is the scverse R interoperability package.
  It reads and writes h5ad and zarr, and its main job is converting between `AnnData`, `SingleCellExperiment` and `Seurat`.
  It has a small API (9 exports, about 11.5k lines of R), several interchangeable backends (in memory, HDF5, Zarr and reticulate) and R-first data structures (`data.frame`, `Matrix`, plain lists).
- **anndata.claude** is a port of Python anndata 0.13.4 to R.
  It aims for the same behaviour as Python (values, errors, warnings, printed output and files) and for files that are structurally equivalent to Python's.
  It has a wider API (about 20 exports, about 14.8k lines of R plus a small C helper) and covers `raw`, views, backed mode, lazy reading, `concat()`, legacy formats and the other Python readers.
  It has no `SingleCellExperiment` or `Seurat` conversion.

anndataR is the better choice today for moving data between R single-cell ecosystems.
It is mature, reviewed by scverse, on Bioconductor and faster on large files.
anndata.claude is far more faithful to Python anndata, both in features and on disk.
In the checks below Python read back every element it wrote unchanged, where anndataR wrote files that Python could not read or that had changed values or types.
But anndata.claude is young, unreleased, written by an agent loop, depends on a development version of Rarr and has no ecosystem conversion.
The two are more complementary than competing.

## Key functionality

| Area | anndataR 1.3.3 | anndata.claude 0.0.6.9000 |
| --- | --- | --- |
| Goal | Interoperability and conversion | Parity with Python anndata 0.13.4 |
| Object model | R6 `AbstractAnnData` with `InMemoryAnnData`, `HDF5AnnData`, `ZarrAnnData` and `ReticulateAnnData` | One R6 `AnnData`, with backed, lazy and view as states |
| h5ad read and write | Yes | Yes |
| zarr read and write | v2 and v3 | v2 and v3 read, v3 write only (no v2 or `.zarr.zip` write) |
| Compression | h5ad: gzip, lzf (not booleans, #513). zarr: gzip, blosc, zstd, lzma, bz2, zlib, lz4 (default none) | gzip, lzf, zstd, blosc and zarr sharding |
| Python dtypes on disk | Not kept (float32 becomes float64, for example) **(run)** | Kept **(run)** |
| `raw` | No (#259), dropped on read **(run)** | Yes |
| Views | `AnnDataView`, a lazy subset applied when converted | Lazy views with copy-on-write, as in Python |
| File-backed objects | `HDF5AnnData` / `ZarrAnnData` read and write slots in the file, `backed = TRUE` gives `DelayedArray` X | h5ad backed mode as in Python (partial reads, in-place writes, `chunked_X()`) |
| Lazy reading | Only X through `DelayedArray` | `read_lazy()` and `read_elem_lazy()` for every slot |
| `concat()` | No (#325) | Yes, all Python merge strategies |
| Files from anndata < 0.8 | Refused as "not a valid H5AD file" **(run)** | Read with Python's warnings **(run)** |
| Other readers | None | csv, mtx, text, excel, hdf, umi_tools and `write_csvs()` |
| Path inside an HDF5 file | No (#466) | No |
| SingleCellExperiment | `as_SingleCellExperiment()`, `from_SingleCellExperiment()` | No |
| Seurat | `as_Seurat()`, `from_Seurat()` | No |
| Python bridge | `ReticulateAnnData` wraps a live Python object | None (Python is used in tests only) |
| Python anndata 0.13 | Partly supported, with a warning (#514) | The reference version |
| Rec-arrays | Read as dicts and written back as dicts **(run)** (#409) | Kept, with field dtypes, through a C helper |
| Awkward arrays | No (#404) | No |
| Tests | 359 `test_that` blocks | 860 `test_that` blocks, with Python-generated fixtures and tables of expected behaviour |

## Spot checks

### Round trip of every encoded element

Python wrote 160 h5ad files, each with one element from this repository's fixtures (`tests/testthat/fixtures/h5ad`) in `uns$e`.
These cover every dtype of dense and sparse arrays, categoricals, nullable arrays, strings, data frames, scalars, dicts and rec-arrays.
Each R package read the file and wrote it back, then Python compared the element with the original using `anndata.tests.helpers.assert_equal()` **(run)**.

| Result | anndataR | anndata.claude |
| --- | --- | --- |
| Equal, same encoding and dtype | 111 | 155 |
| Equal, different encoding or dtype | 0 | 2 |
| Python reads it but values differ | 31 | 0 |
| Python cannot read the file | 14 | 0 |
| R did not write the element | 4 (plus 4 nested `AnnData` dropped) | 3 (by design) |

- 13 of anndataR's 14 unreadable files have non-ASCII strings (in string arrays, categoricals, data frame indices and rec-arrays), and Python fails with `UnicodeDecodeError` (see #400 below).
  The other is a data frame with a `uint8` column, which anndataR skips with a warning but leaves a group without its `column-order` attribute.
- anndataR's 31 changed values include complex arrays and uint8 (not written), the int32 minimum (read as `NA`), boolean and numeric categoricals, boolean sparse matrices ("NAs introduced by coercion"), most data frame column dtypes (int8, int32, float32, nullable integers), any non-string or duplicate data frame index and rec-arrays.
- anndata.claude refuses complex64 arrays and rec-arrays with int64 values of 2^53 or more, with classed errors that name the path, and both are listed in `vignette("deviations")`.
  Its two "different encoding" cases are a bytes scalar and a complex scalar.

### PBMC 3k structure

The PBMC 3k file (after a Python rewrite) was read and written by each package and its HDF5 tree compared with the source **(run)**.
anndata.claude's file had the same 70 nodes with the same encodings and dtypes.
anndataR's file was missing `raw`, wrote `float32` arrays (X, `obsm`, `varm`, `uns/pca`) as `float64`, `int8` category codes as `int64`, length-1 arrays as scalars and rec-arrays as dicts.

### Performance and memory

Best of three runs (each in a new R process, after loading the package) for PBMC 3k, and one run for the 4 GB file (cellxgene vascular, 84k cells, a Python rewrite of an 800 MB download) **(run)**.
Python times are from `.scratch/hardening/benchmarks.md`, measured the same day on the same machine.

| File | Operation | anndataR (s) | anndata.claude (s) | Python (s) |
| --- | --- | --- | --- | --- |
| PBMC 3k | `read_h5ad` | 0.8 | 1.7 | 0.09 |
| PBMC 3k | `write_h5ad` | 1.3 | 1.1 | 0.09 |
| PBMC 3k | `write_zarr` | 1.8 | 2.8 | 0.71 |
| PBMC 3k | `read_zarr` | 0.5 | 1.8 | 0.13 |
| 4 GB | `read_h5ad` | 10.9 | 35.7 | 5.8 |
| 4 GB | `write_h5ad` | 5.5 | 24.5 | 15.3 |
| 4 GB | `write_zarr` | 20.6 | 85.1 | 16.2 |
| 4 GB | `read_zarr` | 13.0 | 112.3 | 10.0 |

| 4 GB file | anndataR | anndata.claude |
| --- | --- | --- |
| Peak memory, `read_h5ad()` only | 3.0 GB | 5.4 GB |
| Peak memory, all four operations | 8.4 GB | 9.4 GB |
| Memory after loading the package | 0.25 GB | 0.53 GB |
| h5ad written | 1.9 GB | 3.8 GB |
| zarr written | 1.6 GB | 0.6 GB |

The comparison is not like for like.
The 4 GB file has a `raw/X` as large as `X`, which anndataR skips, so anndataR reads and writes about half the data.
anndataR also writes no compression to zarr by default while anndata.claude follows Python's zstd default, which makes its store much smaller but its writes slower.
Even so, on the 4 GB file anndataR is 3 to 5 times faster than anndata.claude on h5ad and about 9 times faster on zarr reads.
On PBMC 3k the gap is smaller, and anndata.claude writes h5ad slightly faster.
anndataR's h5ad write is faster than Python's here, again because it skips `raw`.

## Open anndataR issues addressed in anndata.claude

Checked against the issue text, and on both packages where marked **(run)**.

- **#400 `UnicodeDecodeError` reading in Python** (labelled "needs info").
  Reproduced with a minimal case: an `obs` column with `"café"` written by anndataR to h5ad cannot be read by Python, because the strings are written with the ASCII character set **(run)**.
  anndata.claude writes UTF-8 and Python reads the value back **(run)**.
- **#542 and #545 integer and logical matrices with `NA`.**
  anndataR writes them, then both anndataR and Python fail to read the integer matrix from zarr and the logical matrix from h5ad and zarr **(run)**.
  anndata.claude refuses to write them, with "contains missing values, which need a nullable encoding" **(run)**, which matches Python, where these arrays cannot hold missing values.
- **#537 stale `obsm` data frame index after renaming.**
  After `obs_names<-` on an `HDF5AnnData` opened `r+`, Python refuses the file ("value.index does not match parent's obs names") **(run)**.
  In anndata.claude, renaming a backed object and calling `write()` gives a file that Python reads with the new names in both `obs` and `obsm` **(run)**.
- **#531 out-of-range sparse indices.**
  anndataR fails with a cli parse error ("Could not parse cli `{}` expression") **(run)**.
  anndata.claude gives "its data, indices and indptr do not describe a 5 x 4 matrix" **(run)**.
  Python 0.13.4 reads the same file without any error **(run)**, so anndata.claude is stricter than Python here, and this is not listed in the deviations vignette.
- **#256 duplicate `obs`/`var` names.**
  anndataR fails with "duplicate 'row.names' are not allowed" **(run)**.
  anndata.claude keeps the duplicates and gives Python's warning **(run)**.
- **#134 files from anndata < 0.8** are read by anndata.claude, and anndataR refuses the legacy PBMC 3k file **(run)**.
- **#259 `raw`** and **#325 `concat()`** are implemented.
- **#409 rec-array conformance** and **#513 boolean compression** are handled by the C helper and the compression layer.
- **#541 zarr chunking** and **#461 consolidated zarr metadata** are handled: arrays are chunked (and can be sharded) and `zarr_consolidate()` writes the root metadata.
- **#444 missing values in string arrays.**
  anndata.claude uses Python's nullable string encoding instead of an `"NA"` sentinel.
- **#301 integer overflow on large files.**
  anndata.claude reads 64-bit `indptr` and values as doubles where needed (`bit64conversion = "double"`), but I did not test a file with more than 2^31 non-zero values.
- **#500 zarr scalar strings.**
  Both packages write a scalar string with `data_type: "string"`, as Python 0.13.4 does **(run)**, so the issue is a gap between Python's writer and the format spec and not an anndataR bug.

Not addressed in anndata.claude: awkward arrays (#404), reading and writing at a path inside an HDF5 file (#466), and everything about conversion to Seurat or SingleCellExperiment (#399, #388, #390, #271, #338, #476, #459, #337 and #414).

### New anndataR finding

A length-1 vector in a data frame is written as a scalar (`string` or `numeric-scalar`) and not an array, in both h5ad and zarr **(run)**.
So an object with one variable (its `var` index) or one observation (the `obs` index and every `obs` column) gives a file that Python cannot read ("Index(...) must be called with a collection of some kind") **(run)**.
The cause is the `length(value) == 1` checks in `write_h5ad_element()` and `write_zarr_element()`, and I found no open issue for it.

## Differences in implementation

- **Class design.**
  anndataR separates an abstract class from concrete backends, so the same API sits on memory, a file or a Python object, and file-backed objects write each slot to disk when it is set.
  anndata.claude has one class and treats backed, lazy and view as states of it (ADR 0002 chooses R6 for Python's reference semantics).
- **Annotations.**
  anndataR stores `obs` and `var` as base `data.frame`, so duplicate or `NA` row names cannot be represented.
  anndata.claude uses `S4Vectors::DataFrame` (ADR 0003), which allows them and keeps pandas dtype records and the index name.
- **I/O layer.**
  anndataR has separate readers and writers for h5ad and zarr (#445 asks for shared helpers) and chooses the encoding from the R type, so a length-1 vector becomes a scalar and missing values pick the nullable encoding.
  anndata.claude has an element registry keyed by Python's encoding names, over a store layer with HDF5 and zarr backends, so each encoding is written once for both formats.
- **On-disk dtypes.**
  anndata.claude keeps an `anndata_dtype` record on arrays so that `uint8`, `float32`, `int64` and similar types survive a round trip.
  anndataR maps everything to R's types.
- **Compiled code.**
  anndata.claude has a small C helper, linked to `Rhdf5lib`, for HDF5 compound types, which rhdf5 cannot read or build (ADR 0008).
  anndataR has no compiled code.
- **Zarr writer.**
  anndata.claude writes `zarr.json` itself and uses Rarr only for chunk data, which gives variable-length strings, scalars, sharding and consolidated metadata.
  anndataR leaves more to Rarr.
- **Specification and tests.**
  anndata.claude treats Python anndata 0.13.4 as the only reference (ADR 0001) and tests against Python-generated files and JSON tables of expected values, warnings and errors.
  Its spec forbids using other R implementations as a reference, so the designs are independent.
  anndataR tests with its `generate_dataset()` generators and Python round trips, and tracks known failures in `inst/known_issues.yaml`.
- **Development process.**
  anndataR is developed by a team with scverse review and CI against Bioconductor.
  anndata.claude was written by an autonomous agent loop (Ralph) from specs, tickets and ADRs, checked by a separate reviewer agent, and has not had a full human code review.

## Dependencies

| | anndataR | anndata.claude |
| --- | --- | --- |
| R version | >= 4.5.0 | >= 4.3 |
| Imports | cli, lifecycle, Matrix, methods, purrr, R6, reticulate, rlang, stats | BiocGenerics, cli, DelayedArray, jsonlite, lifecycle, methods, Matrix, R6, Rarr, rhdf5, rlang, S4Arrays, S4Vectors, SparseArray |
| HDF5 and zarr | `rhdf5` and `Rarr` in Suggests (checked at use) | `rhdf5` and `Rarr` in Imports |
| Compiled code | No | Yes (`LinkingTo: Rhdf5lib`, GNU make) |
| Unreleased dependencies | No | `Rarr@devel` through `Remotes:` (ADR 0007) |
| Conversion packages | SingleCellExperiment, SummarizedExperiment, Seurat and SeuratObject in Suggests | None |
| Python | `reticulate` is a hard import | Tests only (through `uv`) |

anndataR is lighter to install and keeps the heavy packages optional, but always needs `reticulate`.
anndata.claude has a heavier Bioconductor footprint, needs a C toolchain and a development version of Rarr, and could not go to Bioconductor before Rarr 2.1.48 is released.

## Pros and cons

### anndataR

Pros:

- Conversion to and from `SingleCellExperiment` and `Seurat`, which is what most R users need
- Official scverse package with several maintainers, releases, Bioconductor and CI against several Python versions
- 3 to 9 times faster than anndata.claude on a large file (partly because it skips `raw`), and less memory to read
- Light hard dependencies and a smaller code base
- Several backends, including a live Python object through `reticulate`
- Familiar R data structures (`data.frame`, `Matrix`)

Cons:

- Files it writes can be unreadable in Python (non-ASCII strings, `NA` in matrices, length-1 string arrays in zarr, stale indices after renaming)
- Dtypes are not kept, `raw` is dropped and rec-arrays become dicts
- No `concat()`, full lazy reading, legacy files or other readers
- Duplicate or missing `obs`/`var` names cannot be read
- Python anndata 0.13 is only partly supported (#514)
- `reticulate` is required even for file-only use

### anndata.claude

Pros:

- Nearly all of Python anndata's behaviour, with a deviations vignette listing every difference
- Files that match Python's (dtypes, encodings, compression, rec-arrays and sharding), checked against Python in its tests and in the round trips above
- `raw`, views, backed mode, lazy reading and `concat()`
- Python anndata 0.13.4 is the explicit target
- Large test suite and a registry design that makes new encodings cheap to add
- Clear, classed errors where anndataR fails late or with an unrelated message

Cons:

- No `SingleCellExperiment` or `Seurat` conversion, so it does not replace anndataR for most R workflows
- Not published or reviewed by a person, and written by an agent, so long-term maintenance and trust are open questions
- Needs an unreleased Rarr and a C toolchain, and has a large dependency tree
- Slow on large files: 1.6 to 6 times slower than Python on h5ad and about 11 times slower on zarr reads, and about twice anndataR's memory to read h5ad
- Python-style API (R6 reference semantics, `copy()`) may surprise R users
- No zarr v2 or zip writing, and complex64 arrays cannot be read

## Other points of interest

- Luke Zappia is an author of both packages, but anndata.claude's spec forbids using anndataR as a reference, so the designs are independent.
- Converters to `SingleCellExperiment` and `Seurat` could be built on anndata.claude's `AnnData`, but they are not in its roadmap.
  Alternatively, anndataR could use anndata.claude for file I/O and keep its converters.
- Many open anndataR bugs come from choosing the encoding from the R type at write time.
  anndata.claude avoids them by keeping Python's dtype and encoding on the R value.
- My first benchmark script made writes in both packages hundreds of times slower (anndataR's 4 GB h5ad write took 909 s against 5.5 s in a simple script).
  I did not find the cause, so the tables above use only the simple script.

## Not verified

- Memory use for #329 was measured on one file only, and #301 was not tested with more than 2^31 non-zero values.
- No conversion features (Seurat or SingleCellExperiment) were tested.
- Backed and lazy performance were not compared.
- Benchmarks are single runs on one machine, and anndata.claude was loaded with `pkgload::load_all()` and not installed.
