# Python anndata is the sole reference and on-disk compatibility comes first

`anndata.claude` is an R port of Python anndata, using only the Python implementation and documentation as its reference (pinned to release 0.13.4).
Existing R implementations are deliberately ignored, so they must not be used for API design, code or behaviour.
Byte-level compatibility with the anndata on-disk format (h5ad, later zarr) is the top priority, and the in-memory object exists to support it, with full feature parity as the long-term goal and an MVP first.
The package is not intended for publication, so dependencies are chosen for effectiveness rather than CRAN or Bioconductor eligibility, but it must have tests and pass `R CMD check`.
