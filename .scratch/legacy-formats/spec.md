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

Orchestrator, 2026-10-23, after the spike (`.scratch/legacy-formats/releases-spike.md`):

- Fixtures come from 0.6.22.post1 (h5ad), 0.7.8 (h5ad and zarr) and 0.10.9 (the `uns["neighbors"]` move, h5ad and zarr), driven by one `tests/python/legacy_fixtures.py` with the release pins kept in the script
- Unsupported and untested, because no installable release exercises them or Python 0.13.4 cannot read them:
  - 0.6.x zarr stores (0.13.4 fails with `No Zarr data type found that matches {'name': '|O', 'object_codec_id': 'json2'}`), so the zarr branches of `read_dataframe_legacy`, `raw.X`/`raw.var`, `_clean_uns` and h5sparse groups
  - layouts only written before 0.6 (0.5.x does not install)
  - the multicolumn `obs_keys_multicol`, `smp_keys_multicol` and `var_keys_multicol` handling of `_clean_up_old_format`
  Reading one of these gives whatever the shared readers do, with no promise of matching Python.
