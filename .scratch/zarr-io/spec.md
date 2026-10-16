# zarr I/O

Status: ready-for-agent

Sub-project 6 of the roadmap (`.scratch/roadmap/spec.md`), the first after the MVP.
It reads and writes zarr stores (v3 and v2) with the same Element encodings and Round trip guarantees as h5ad (`.scratch/h5ad-io/spec.md`), so that a Round trip between R and Python preserves every Element, in either format.

Python references are relative to `.reference/anndata/`: `src/anndata/_io/zarr.py` (written as `zarr.py`), `src/anndata/_io/specs/methods.py` (`methods.py`), `src/anndata/_settings.py`, `docs/tutorials/zarr-v3.md` and release notes 0.13.0 and 0.13.4.
The spike findings are in `.scratch/zarr-io/zarr-spike.md`.

## Decisions (human, 2026-10-16)

First grilling round:

- Start with a research and spike ticket (zarr-io/01), considering only packages on CRAN or Bioconductor
- Versions: read v2 and v3, write v3 by default and v2 with `zarr_write_format = 2`, and support `auto_shard_zarr_v3`, as Python does.
  v3 is the priority, so tickets do all of v3 first, then reading v2, then writing v2 last.
  If writing v2 is expensive, it moves to a follow-up ticket rather than holding back the sub-project.
- Stores: local directory stores now, zip stores only if the chosen library supports them (it does not, so they are a follow-up), remote stores out of scope
- Fallback order if a library falls short: the closest library with small wrappers, then our own implementation of the subset of zarr anndata uses, then a compiled binding.
  Python (reticulate) is never used at runtime.
- A backend-neutral store abstraction is the agents' decision
- Round trips: the three h5ad directions with Python-written v2 and v3 fixtures, plus a cross-format check
- Structural equivalence is the same as for h5ad: Encoding type, Encoding version, On-disk dtype, shape, values and attributes match.
  Chunk shape, codecs and shard layout need not match but must be readable by Python, and R's defaults follow Python's wherever the library allows.

Second round, after the spike:

- Use Rarr (Bioconductor devel, 2.1.48 or later) with a thin writer layer of our own for what it cannot write (ADR 0007).
  The development versions were compared, and pizzarr main was skipped because it needs a Rust toolchain.
- Reading sharded v3 stores comes with the first v3 read tickets, and writing shards is a later ticket of its own.
  Until it is done, R writes unsharded v3.
- Zip stores are a follow-up ticket outside this sub-project

## Scope

In:

- `read_zarr()`, `write_zarr()` (function and `AnnData` method), and `read_elem()`/`write_elem()` on zarr groups
- Every encoding that h5ad supports, in zarr v3 and v2
- Reading sharded v3 arrays, and writing them under `auto_shard_zarr_v3`
- Reading and writing consolidated metadata (`.zmetadata` in v2, inline in the root `zarr.json` in v3)
- The settings `zarr_write_format` and `auto_shard_zarr_v3`
- Fixtures, round-trip tests and a cross-format check
- A zarr section in the vignette

Out:

- Zip stores (`.zarr.zip`): reading one raises a classed error that suggests unzipping it, as Python adds a note suggesting `ZipStore` (`zarr.py:143-149`).
  A follow-up ticket covers support.
- Remote stores (S3, HTTP, cloud) and arbitrary `MutableMapping` stores
- Legacy layouts (`legacy-formats`), including the backwards-compatible paths in `read_zarr()` (`raw.X`, obs stored as an array, `zarr.py:162-201`).
  Reading one raises the same "not yet supported" classed error as h5ad.
- `awkward-array` (`experimental`), backed and lazy reading (`backed`, `lazy`)

## zarr library

- Rarr does the reading: groups, attributes, every dtype, strings, scalars, sharded arrays and consolidated metadata, in v2 and v3
- Rarr writes groups, attributes, numeric and bool arrays and consolidated metadata.
  Our own writer layer covers what it cannot write (spike, "Recommendation"):
  - variable-length UTF-8 string arrays, as Python writes them (v3 `string` with `vlen-utf8` then `zstd`, v2 `|O` with the `vlen-utf8` filter)
  - 0-dimensional (scalar) arrays
  - the On-disk dtype, always given explicitly, never Rarr's smallest-fitting default
  - int64 and uint64 values held as doubles
  - shards, with a `crc32c` index (its own ticket)
- `Rarr (>= 2.1.48)` is in Imports, with `Remotes: Huber-group-EMBL/Rarr@devel` until that version is released on Bioconductor
- The on-disk (C-order) shape equals R `dim()` for every array, as for h5ad.
  A 0-d array has no `dim()`, so its shape comes from the metadata, never from what Rarr returns.

## Encodings

- Every encoding and version in the h5ad encoding table (`.scratch/h5ad-io/encoding-table.md`) is read and written on zarr stores, through the same element registry
- The zarr-specific differences in Python are followed exactly, including:
  - scalars (`write_scalar_zarr`, `methods.py:1395-1420`): string scalars use the variable-length UTF-8 dtype, with fill value `""` and a `vlen-utf8` filter in v2
  - `null` is a 0-d bool array (`write_null_zarr`, `methods.py:422-430`)
  - compression arguments are dropped for scalars and nulls (`_remove_scalar_compression_args`)
  - the `compressor` argument becomes `compressors` in v3 (`zarr_v3_compressor_compat`)
- A zarr encoding table, generated like the h5ad one, records what Python writes for every case in v2 and v3: dtype, codecs, fill value, attributes and layout.
  It is the reference for the writer layer and is guarded by a freshness test.
- On-disk dtype preservation works as for h5ad, including the 64-bit integer policy (double below 2^53, otherwise a classed error) and the int32 minimum value
- rec-array follows ADR 0005 (values, names and order round trip).
  If zarr makes field dtypes or non-ASCII text easier to preserve than HDF5 does, preserve them.
  If zarr cannot do as well as h5ad, the ticket stops and asks the human.

## Versions, sharding and consolidated metadata

- `zarr_write_format` (default 3) chooses the version written by `write_zarr()` and by `write_elem()` on a new store.
  Setting it to 2 warns as Python does (`zarr.py:244-256`).
- `auto_shard_zarr_v3` (default `TRUE`) shards v3 arrays with a target of 1 GB uncompressed per shard, as Python does (`methods.py:122-145`).
  An explicit `shards` dataset argument overrides it, and the setting is ignored for v2.
  Shard shapes need not match Python's.
  Until the shard-writing ticket is done, R writes unsharded v3 and the settings help page says so.
- `write_zarr(consolidate_metadata = TRUE)` writes consolidated metadata after all Elements, as Python does
- Reading uses consolidated metadata when present and works without it

## Public functions

- `read_zarr(store)`, where `store` is a path to a directory store (`zarr.py:152-201`)
- `write_zarr(adata, store, chunks = NULL, convert_strings_to_categoricals = TRUE, consolidate_metadata = TRUE, ...)`, also available as `adata$write_zarr(store, ...)` (`zarr.py:89-135`, `anndata.py:1793-1830`)
  - `chunks` applies to a dense X only, as in Python
  - `...` are dataset arguments passed to every array, as Python's `**ds_kwargs`, at least for compression (`compressor`/`compressors` with zstd, gzip and blosc) and `shards`
  - `convert_strings_to_categoricals` behaves as in `write_h5ad()`
  - the root group gets `encoding-type: anndata` and `encoding-version: 0.1.0`
- `read_elem()` and `write_elem()` accept a zarr group (and a path within it) as well as an rhdf5 handle, with the same behaviour and errors as for h5ad
- `adata$unwriteable(store_type = "zarr")` follows Python for zarr

## Fixtures

`tests/python/generate_fixtures.py` (or a zarr counterpart) writes each case as a v3 store and a v2 store into `tests/testthat/fixtures/zarr/`, covering at least:

- every case in the h5ad fixture set that has a zarr equivalent, written by Python with its defaults (so v3 stores are sharded and consolidated)
- unsharded and unconsolidated v3 variants, and every compressor Python commonly writes (zstd, blosc, gzip, none)
- the realistic `gen_adata` object

## Round-trip tests

For every fixture, in v3 and v2:

1. **Python → R**: R reads the store and the result matches the expected R values
2. **Python → R → Python**: R writes the object read in step 1, and `expect_structurally_equivalent()` (extended to zarr stores) and `expect_python_equal()` pass against the original
3. **R → Python → R**: an object built in R is written by R, read and rewritten by Python, and read again by R, giving an identical object

Also:

- **Cross-format**: R reads an h5ad fixture and writes it as zarr, and the store is Structurally equivalent to Python's own conversion of the same file (`read_h5ad()` then `write_zarr()`).
  The same holds from zarr to h5ad.
- Everything in the h5ad "Also" list (R → R, unencodable values, legacy and awkward errors, every error and warning) for zarr
- A sharded R-written v3 store reads in Python, once shard writing is done

## Vignette

The vignette gains a short zarr section: writing and reading a store, and moving it to Python and back.

## Acceptance criteria

- Every encoding reads and writes correctly in v3 and v2, with all three round-trip directions passing for every fixture
- The cross-format check passes in both directions
- The zarr encoding table is committed and matches the tests
- `scripts/check.sh` passes
