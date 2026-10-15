# Python reference environment

Status: done
Type: task
Blocked by: 03

## What

Set up the pinned Python reference environment and the R helpers that call it, as described in "Python reference environment" and "R test helpers" in `.scratch/foundations/spec.md`.

- A uv project at `tests/python/` (`pyproject.toml` plus a committed `uv.lock`) pinning `anndata==0.13.4`, `pandas>=3` and current `h5py`, `numpy` and `scipy`.
  The project is not a Python package and exists only for scripts.
- The uv virtual environment is not committed and does not end up in the built package (handle `.venv` in `.gitignore` and `.Rbuildignore` as needed)
- `tests/testthat/helper-python.R` with:
  - `skip_if_no_python()`: skips when `uv` is not on the `PATH` or `ANNDATA_SKIP_PYTHON` is `true`
  - `run_python(script, ...)`: runs `uv run --project <tests/python> python <script> ...`, returns stdout, and fails the test with stderr on a non-zero exit
- The helpers must find `tests/python` both under `devtools::test()` and inside `R CMD check`, where the tests directory is copied
- A smoke test that runs a trivial script which prints the anndata and pandas versions as JSON, and asserts anndata `0.13.4` and pandas major version 3

## Acceptance criteria

- The smoke test passes with `uv` available, and is skipped (not failed) with `ANNDATA_SKIP_PYTHON=true`
- `uv.lock` is committed and the environment builds from it
- `scripts/check.sh` passes

## Comments

- 2026-10-15: Added `tests/python/` uv project (`pyproject.toml`, `uv.lock`, `versions.py`), `tests/testthat/helper-python.R` and `test-python.R`. `.Rbuildignore` now only excludes `tests/python/.venv` and `__pycache__`. Added `jsonlite` to Suggests for parsing script JSON in tests. `run_python()` runs scripts with `python -I` and gives uv its own `TMPDIR`, because uv lock files left in the check temp dir cause a detritus NOTE. Later scripts (`h5_tree.py` etc.) go in `tests/python/` and are called by name.
