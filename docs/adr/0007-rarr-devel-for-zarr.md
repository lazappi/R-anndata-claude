# Rarr's development version is the zarr library

zarr I/O uses Rarr from Bioconductor devel (2.1.48 or later), declared with a `Remotes:` entry until that version is released.
The spike (`.scratch/zarr-io/zarr-spike.md`) compared the development versions of every CRAN and Bioconductor zarr library: only Rarr reads every anndata dtype and layout in v2 and v3, including v3 strings, scalars, sharded arrays and consolidated metadata, with no codec packages or system libraries.
The release version (1.10.1) reads v2 only, the CRAN `zarr` package turns fill values into `NA` (which corrupts sparse data), and pizzarr's development version needs a Rust toolchain.
Rarr cannot write variable-length strings, scalars or shards, and narrows integer types by default, so a thin writer layer of our own fills those gaps rather than our own zarr implementation.
Depending on unreleased code is acceptable because the package is not published, and the `Remotes:` entry is dropped once Bioconductor releases it.
