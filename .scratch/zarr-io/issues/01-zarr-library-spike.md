# zarr library spike

Status: ready-for-agent
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
