# Legacy formats

Status: needs-triage

Stub spec, to be grilled into a full spec before tickets are written.
Sub-project 9 of the roadmap (`.scratch/roadmap/spec.md`).

## Goal

Read files written by older anndata versions whose layouts predate the current encodings, as Python 0.13.4 does.
Writing always uses the current encodings.

## Scope

- Unencoded elements (`IOSpec("", "")`, `methods.py:202-204`)
- h5sparse legacy attributes in `sparse_dataset()` (the `legacy_attributes` row of the backed operations table, moved here from backed/04)
- `dataframe` 0.1.0 (`methods.py:1133`) and legacy dataframes stored as datasets (`h5ad.py:332-355`)
- Categories stored in `uns["<col>_categories"]` (`anndata.py:1921-1947`, `_clean_up_old_format`)
- Old `uns["neighbors"]` connectivities moved to obsp (`_move_adj_mtx`)
- The zarr equivalents of all of the above that `read_zarr()` handles (`src/anndata/_io/zarr.py:152-235`)

## Python references

- `src/anndata/_io/specs/methods.py:202-330`
- `src/anndata/_io/h5ad.py:332-380`
- `src/anndata/_core/anndata.py:1921-1947`

## Decisions (human, 2026-10-22)

- Legacy fixtures come only from real old anndata releases, installed in separate `uv` environments with whatever older Python, numpy and h5py they need.
  No hand-written fallback: a layout that no installable release produces is listed as unsupported and untested, with Python 0.13.4's behaviour noted, rather than hand-crafted.
- Cover every legacy layout Python 0.13.4 reads, for h5ad and zarr (`read_zarr()`'s backwards-compatible paths, such as `raw.X` and obs stored as an array)
- The PBMC 3k download is read directly in the real-world test (no Python rewrite first)
- Follow Python for everything else: `OldFormatWarning` where Python raises it, legacy files through backed and lazy reading, and writing always in the current encodings
- A spike (legacy-formats/01) finds which releases install and which layouts each produces, then the orchestrator finishes the spec and writes the tickets, asking the human only if there is no clear choice

## Open questions

- Which releases install and which layouts they produce (spike legacy-formats/01)
