# legacy-formats: fixture generator and expectation table

Status: ready-for-agent
Type: task
Blocked by: none

## What

Generate legacy fixtures from real old releases and record what Python 0.13.4 reads from them (see `.scratch/legacy-formats/releases-spike.md`).

- One `tests/python/legacy_fixtures.py`, outside `generate_fixtures.py` because it does not run in the pinned environment
- It drives `uv run --no-project --isolated --python <v> --with anndata==<release> ...` once per release with the pins in the spike table: 0.6.22.post1 (h5ad only, zarr stores are unreadable by 0.13.4), 0.7.8 (h5ad and zarr) and 0.10.9 (h5ad and zarr, for the `uns["neighbors"]` move)
- 0.7.0 is skipped (same layout as 0.7.8) and so is 0.8.0 (already a current layout)
- 0.10.9 (h5ad and zarr) writes only the `uns["neighbors"]` connectivities and distances case, which ticket 05 needs
- Each release writes a dense and a CSR `AnnData` as in the spike, plus `varm` and `raw.varm` for 0.6.22 to settle the open `raw.varm` question
- Expectations are JSON written by a `tests/python/*_cases.py` script into `tests/testthat/fixtures/` (values, warning classes and messages per file, from reading with 0.13.4), guarded by a freshness test as in `make_unique_cases.py`, and wired into `scripts/regenerate-fixtures.sh`
- The 0.6.22 zarr error and the zarr-only legacy paths with no installable release are recorded as unsupported (see the spike's "Legacy read paths no installable release exercises"), with 0.13.4's behaviour noted

## Acceptance criteria

- Fixtures and the expectation table are committed and a freshness test passes
- The table has one row per fixture with the values and warnings 0.13.4 gives
- The unsupported layouts are listed in the table file with 0.13.4's error or behaviour
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments
