# Legacy formats

Status: needs-triage

Stub spec, to be grilled into a full spec before tickets are written.
Sub-project 9 of the roadmap (`.scratch/roadmap/spec.md`).

## Goal

Read files written by older anndata versions whose layouts predate the current encodings, as Python 0.13.4 does.
Writing always uses the current encodings.

## Scope

- Unencoded elements (`IOSpec("", "")`, `methods.py:202-204`)
- `dataframe` 0.1.0 (`methods.py:1133`) and legacy dataframes stored as datasets (`h5ad.py:332-355`)
- Categories stored in `uns["<col>_categories"]` (`anndata.py:1921-1947`, `_clean_up_old_format`)
- Old `uns["neighbors"]` connectivities moved to obsp (`_move_adj_mtx`)

## Python references

- `src/anndata/_io/specs/methods.py:202-330`
- `src/anndata/_io/h5ad.py:332-380`
- `src/anndata/_core/anndata.py:1921-1947`

## Open questions

- Which older anndata releases should generate the fixtures (e.g. 0.6.x and 0.7.x through `uv`), and do they still install on current Python?
