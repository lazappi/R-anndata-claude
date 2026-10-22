# legacy-formats: fixture generator and expectation table

Status: done
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

2026-10-23: Done.

- `tests/python/legacy_fixtures.py` drives the three releases (it is also the writer inside each old environment, `--write`) and writes `tests/testthat/fixtures/legacy/<tag>-<case>.h5ad` plus `legacy-zarr-fixtures.tar.gz` (zarr stores, gitignore exception added). Files are `0.6.22-{dense,sparse}.h5ad`, `0.6.22-dense.zarr`, `0.7.8-{dense,sparse}.{h5ad,zarr}`, `0.10.9-neighbors.{h5ad,zarr}`
- I also wrote one 0.6.22 zarr store, so the unreadable-store error in the unsupported list comes from a real file
- `tests/python/legacy_cases.py` writes `legacy_cases.json` (`fixtures[<file>]` has `status`, `values` or `error`/`message`, and `warnings`, plus an `unsupported` list). Both scripts are in `regenerate-fixtures.sh` and `legacy_cases.py` (with `legacy_fixtures.py` as extra input) has a freshness test in `test-legacy-fixtures.R`
- 0.13.4 reads members and raises warnings in a different order on every run, so the table sorts dict keys (`uns`, `obsp`, mappings) and warnings, and an error row has no warnings
- Every old fixture also has `varm["PCs"]`, and `a.raw = a` gives `raw.varm`: 0.6.22 writes `raw.varm/PCs` as a root member (`/raw.varm/PCs`), and 0.13.4 reads it into `raw.varm`. This settles the open question for ticket 05
- 0.6.22 files also give the `uns["neighbors"]` `FutureWarning`, not only `OldFormatWarning`
- Reading the h5ad fixtures prints the zarr 0.6.22 traceback on stderr (an unretrieved asyncio task), which is harmless
