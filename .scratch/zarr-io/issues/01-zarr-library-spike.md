# zarr library spike

Status: needs-info
Type: research
Blocked by: none

## What

Choose the R zarr library for `zarr-io` (see the decisions in `.scratch/zarr-io/spec.md`).
Consider only packages on CRAN or Bioconductor (for example `Rarr`, `pizzarr` and the CRAN `zarr` package, plus any others found).

For each candidate, record a pass, gap or workaround verdict for:

- reading and writing zarr v3, and separately v2
- sharding (v3) and consolidated metadata (`.zmetadata` and v3 consolidated metadata)
- the dtypes anndata writes: every integer and float width signed and unsigned, bool, variable-length UTF-8 strings (v2 `vlen-utf8` and the v3 string data type), and 0-dimensional (scalar) arrays
- the codecs Python writes by default (find them with `python-oracle` from the pinned zarr in `tests/python`), including zstd and blosc
- group and array attributes, including array-valued and JSON-object attributes
- reading partial chunks or slices (needed later by `backed` and `lazy`)
- zip stores (`.zarr.zip`)
- how the on-disk C-order shape maps to R `dim()`, and how missing chunks and fill values behave
- maintenance status, dependencies (including system libraries) and licence

Evidence comes from Python-written fixtures (v2 and v3, written with anndata 0.13.4 and its pinned zarr) that each candidate reads, and from files each candidate writes that Python reads back.
Install candidates into the user library with `Rscript -e 'install.packages(...)'` or `BiocManager::install()`.
Keep the comparison of candidates out of the package: scripts and their output live under `.scratch/zarr-io/spike/`, and only the recommended library is added to `DESCRIPTION` (Imports), with package tests for its verdicts.

Also recommend:

- the library, with the gaps it leaves and how to fill them, following the fallback order in the spec
- whether the h5ad element registry should gain a backend-neutral store abstraction, and its rough shape
- any codec packages needed

## Acceptance criteria

- A findings document is committed at `.scratch/zarr-io/zarr-spike.md` with a verdict for every item above for every candidate, and the recommendations
- Each verdict for the recommended library is backed by a package test that reads a Python-written fixture or writes a file that Python reads back
- `scripts/check.sh` passes

## Comments

2026-10-16 (loop run)

Done: findings document `.scratch/zarr-io/zarr-spike.md` with a verdict for every item for Rarr, pizzarr and zarr (blosc covered as a codec package), the recommendation (pizzarr with wrappers, and the store abstraction shape), probe scripts in `.scratch/zarr-io/spike/`, `tests/python/zarr_spike_fixtures.py` and `tests/python/zarr_describe.py`, `pizzarr` added to `DESCRIPTION` Imports (placeholder `@importFrom` in the package file), and `.scratch` excluded from lintr (throwaway scripts).

Not done, the package tests for pizzarr's verdicts (acceptance criterion 2).
They are written (23 expectations over 15 tests, 123 passing under `scripts/check.sh --quick`) but fail under the full `R CMD check` with `blosc package must be installed to use the Blosc codec`, for the Python-written v2 stores (Python's v2 default compressor is blosc/lz4).
`blosc` is installed and loads in the same `.libPaths()` in a separate session, and the same tests pass under `devtools::test()`.
Tried: reinstalling `zlib`/`stringfish`/`RcppParallel` (unrelated pizzarr load failure, fixed), a `.libPaths()` and `loadNamespace("blosc")` diagnostic inside the check (libs are the user and system libraries, the loadNamespace line was not captured), and three full check runs.
The tests are in the git stash `zarr-io/01: pizzarr verdict tests (fail under R CMD check, blosc)`, apply it with `git stash pop`.

Questions for the human:

1. Is `blosc` (GPL (>= 3), needs `libblosc`) acceptable as a dependency for a BSD-3 package? pizzarr needs it for any blosc-compressed chunk, which includes every Python-written v2 store.
   If not, v2 reading needs our own blosc decoding (fallback step 2) or must be dropped.
2. Why does pizzarr not see `blosc` under `R CMD check`? Recommended next step: run the failing test under `R CMD check` with `loadNamespace("blosc")` printed (the output was not captured above) before deciding.
3. Given the gaps (v3 strings, v3 scalars, sharding, empty v2 strings, consolidated writing), is pizzarr plus wrappers acceptable or should zarr-io go to fallback step 2 (own R implementation of the zarr subset, reusing pizzarr's codecs)? Recommended: pizzarr for metadata, groups, attributes and numeric chunks, and our own string and sharding codecs.

Recommended answer to 1: accept `blosc` in Suggests only (v2 blosc reading and tests then skip when it is absent), pending the human's call.
