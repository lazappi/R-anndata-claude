# zarr I/O

Status: needs-triage

Stub spec, to be grilled into a full spec before tickets are written.
Sub-project 6 of the roadmap (`.scratch/roadmap/spec.md`).
Important, but after the MVP.

## Goal

`read_zarr()` and `write_zarr()` with the same Element encodings as h5ad, for zarr v3 (the default) and v2 (deprecated upstream), with Round trip guarantees equal to h5ad's.

## Scope

- `read_zarr()`, `write_zarr()` (including `consolidate_metadata`) and the `adata$write_zarr()` method
- `read_elem()`/`write_elem()` dispatch on zarr stores
- The settings `zarr_write_format` and `auto_shard_zarr_v3` (sharding with a 1GB target)
- zarr-specific encoding differences (e.g. scalar strings, `methods.py:1395-1420`)
- Single-file stores such as `.zarr.zip`, if an R library supports them

## Python references

- `src/anndata/_io/zarr.py`
- `src/anndata/_io/specs/methods.py` (the zarr registrations)
- `docs/tutorials/zarr-v3.md`
- Release notes 0.13.0 and 0.13.4

## Decisions (human, 2026-10-16, first grilling round)

- Start with a research and spike ticket (zarr-io/01) that compares R zarr libraries, followed by a human checkpoint and a second grilling round on the library-dependent questions
- Only packages on CRAN or Bioconductor are considered
- Versions: read v2 and v3, write v3 by default and v2 with `zarr_write_format = 2`, and support `auto_shard_zarr_v3`, as Python does.
  v3 is the priority, so tickets do all of v3 first, then reading v2, then writing v2 last.
  If writing v2 is expensive with the chosen library, it moves to a follow-up ticket rather than holding back the sub-project.
- Stores: local directory stores now, zip stores (`.zarr.zip`) only if the chosen library supports them, and remote stores (S3, HTTP, cloud) out of scope for now (follow-up)
- If no library is good enough, fall back in this order: the closest library with small wrappers around its gaps, then an R implementation of the subset of zarr anndata uses (JSON metadata, chunk files and codecs from existing packages), then a compiled binding to a C++ or Rust zarr library.
  Python (reticulate) is never used at runtime.
- Whether the h5ad element registry gains a backend-neutral store abstraction (shared encoding logic for HDF5 and zarr) is an implementation decision for the agents, informed by the spike's recommendation, and any refactor must leave h5ad behaviour unchanged
- Round trips: the three h5ad directions with Python-written v2 and v3 fixtures, plus a cross-format check (an h5ad file that R reads and writes as zarr is Structurally equivalent to Python's own conversion)
- Structural equivalence for zarr is the same as for h5ad: Encoding type, Encoding version, On-disk dtype, shape, values and attributes must match.
  Chunk shape, codecs and shard layout need not match, but must be readable by Python, and R's defaults follow Python's wherever the library allows.

## Open questions

- Which R zarr library (e.g. `Rarr`, `pizzarr` or another) supports v3, sharding, consolidated metadata, variable-length strings and the needed codecs?
  This needs a research and spike ticket before anything else.
