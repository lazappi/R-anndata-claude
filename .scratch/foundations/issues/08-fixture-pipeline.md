# Fixture pipeline and offline mode

Status: ready-for-agent
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
