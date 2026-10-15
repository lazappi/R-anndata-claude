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

## Open questions

- Which R zarr library (e.g. `Rarr`, `pizzarr` or another) supports v3, sharding, consolidated metadata, variable-length strings and the needed codecs?
  This needs a research and spike ticket before anything else.
- Does the element registry from `h5ad-io` need a store abstraction?
  It should be designed for this from the start, but confirm at the time.
