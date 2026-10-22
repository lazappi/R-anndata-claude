# Legacy releases spike

Status: done
Type: research
Blocked by: none

## What

Find out which old anndata releases can still be installed and which legacy layouts each writes (see the decisions in `.scratch/legacy-formats/spec.md`).

- For each candidate release (for example the last 0.6.x, 0.7.x and 0.8.x, and any earlier one a legacy read path in 0.13.4 names), try a separate `uv` environment under `tests/python/legacy/<release>/` with the newest Python and the numpy, pandas, h5py and zarr versions it supports
- For each release that installs, write a small h5ad file and zarr store covering every layout it can produce, and record which of Python 0.13.4's legacy read paths (`methods.py:202-330`, `h5ad.py:332-380`, `zarr.py:152-235`, `anndata.py:1921-1947`, the `h5sparse` attributes) each file exercises, and what 0.13.4 reads from it (values and warnings)
- List every legacy read path no installable release exercises (these become unsupported, per the decisions)
- Scripts are throwaway and live in `.ralph/oracle/`, except the environment definitions, which are committed if the recommendation keeps them

## Acceptance criteria

- `.scratch/legacy-formats/releases-spike.md` lists the releases tried (installed or why not), the layouts each produces mapped to the 0.13.4 read paths, the uncovered read paths, and a recommendation for the fixture generator
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: Probed 0.5.10 (not installable), 0.6.22.post1, 0.7.0, 0.7.8, 0.8.0 and 0.10.9, all written as h5ad and zarr and read with 0.13.4.
Findings and the fixture generator recommendation are in `.scratch/legacy-formats/releases-spike.md`.
Key points: 0.6.22 is the only fully unencoded layout (compound `obs`/`var`, `*_categories` in `uns`, `raw.X`, h5sparse groups), 0.7.x gives dataframe 0.1.0 with `__categories`, 0.8.0 is already current, and 0.6.22 zarr stores cannot be read by 0.13.4 at all (zarr 3 has no object dtype).
`scripts/check.sh --package` (0 errors, warnings and notes) and `--tests` (22778 passed) both pass, and the reviewer's findings (values, warnings, `_clean_up_old_format` and `raw.varm` gaps) were addressed in the doc.
No environment definitions are committed (pins live in the recommended generator script).
