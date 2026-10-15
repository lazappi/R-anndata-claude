# Structural comparison helpers

Status: done
Type: task
Blocked by: 06

## What

Add the Python scripts and R expectations used to check Structural equivalence and Round trip equality (see `CONTEXT.md` and `.scratch/foundations/spec.md`).

- `tests/python/h5_tree.py <file>` prints JSON describing every group and dataset: path, kind, attributes (names, values and stored types, including whether strings are variable-length UTF-8), dtype, shape and a value digest (a hash of the values, so large datasets compare cheaply)
- `tests/python/compare.py <a.h5ad> <b.h5ad>` reads both files with `anndata.read_h5ad` and checks them with `anndata.tests.helpers.assert_equal`, exiting non-zero and printing the difference on failure
- R expectations in `tests/testthat/helper-python.R`:
  - `expect_structurally_equivalent(a, b)`: compares the two `h5_tree.py` outputs and lists every differing path and property on failure
  - `expect_python_equal(a, b)`: runs `compare.py`
- `fixture_path(name)`, returning a path under `tests/testthat/fixtures/`
- A smoke test using a small script that writes two tiny h5ad files from Python (one identical to the first, one with a changed dtype), checking that equivalence passes and fails as expected and that the failure message names the path

## Acceptance criteria

- The smoke tests pass, and are skipped without Python
- The failure output of `expect_structurally_equivalent()` is readable (a snapshot test of a failure message)
- `scripts/check.sh` passes

## References

- `.reference/anndata/src/anndata/tests/helpers.py:620` (`assert_equal`)

## Comments

2026-10-15 (human, recovering an interrupted run): The run building this ticket was killed while its checker ran the full check (the check had been moved to the background, see the setup fixes).
Its work is committed as-is in a work-in-progress commit.
`scripts/check.sh` passed on this state when re-run by hand (coverage 81.29%).
`tests/python/pyproject.toml` gained `pytest`, `dask` and `fast-array-utils`, because `anndata.tests.helpers` imports them.
Still to do: confirm every acceptance criterion, run the reviewer (which now reviews all changes since the last tag), then do the bookkeeping, version bump and tag.

2026-10-15 (loop): Confirmed every acceptance criterion. Full `scripts/check.sh` passed (0 errors, warnings or notes, coverage 81.29%) and the reviewer returned PASS. Released as v0.0.0.9006.
Note: `_snaps/comparison.md` embeds digests of the smoke data, so update the snapshot if `write_smoke.py` data changes.
