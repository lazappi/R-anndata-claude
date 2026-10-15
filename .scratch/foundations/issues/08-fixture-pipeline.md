# Fixture pipeline and offline mode

Status: done
Type: task
Blocked by: 07

## What

Create the fixture-generation pipeline that `h5ad-io` and later sub-projects will extend, and confirm that the suite works offline.

- `tests/python/generate_fixtures.py <outdir>` with a simple case registry (e.g. a decorator or dict mapping case name to a function that writes a file).
  It starts with one trivial case so the pipeline is exercised end to end.
  Output files are deterministic (fixed seeds, no timestamps in content that the tests compare).
- A JSON manifest written next to the fixtures listing each case, its file and the reference versions used
- `scripts/regenerate-fixtures.sh` regenerates `tests/testthat/fixtures/` from the reference environment
- Committed fixtures for the trivial case
- A test that reads the manifest and checks every listed fixture file exists
- The full test suite passes with `ANNDATA_SKIP_PYTHON=true`, with Python-dependent tests skipped

## Acceptance criteria

- Running `scripts/regenerate-fixtures.sh` twice produces no Structural equivalence differences (checked by the script or a test)
- `ANNDATA_SKIP_PYTHON=true Rscript -e 'devtools::test()'` passes with skips only
- `scripts/check.sh` passes
- `.scratch/foundations/spec.md` acceptance criteria are all met, so foundations is complete

## Comments

2026-10-15 (loop): Added `tests/python/generate_fixtures.py` (case registry via `@case(filename)`, manifest with anndata/h5py/numpy/pandas versions), `scripts/regenerate-fixtures.sh`, the committed `trivial.h5ad` and `manifest.json`, and `test-fixtures.R`.
The determinism test generates twice into temp dirs and compares each with `expect_structurally_equivalent()` and against the committed fixture, so regenerate and commit fixtures whenever a case changes.
`ANNDATA_SKIP_PYTHON=true devtools::test()` passes with skips only. Full `scripts/check.sh` passed and the reviewer returned PASS. Foundations acceptance criteria are all met. Released as v0.0.0.9007.
