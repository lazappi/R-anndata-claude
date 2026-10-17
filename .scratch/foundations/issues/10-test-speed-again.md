# Faster test suite, again

Status: done
Type: task
Blocked by: none

## What

The full `scripts/check.sh` takes about 490s of its 570s time limit (`R CMD check` 6m47s with 4 test workers), so the next tests added will time out.
Speed the suite up as foundations/09 did, without testing less: measure first (inside one parallel `devtools::test()` call), batch Python calls, and share or shrink zarr and View fixtures where that loses no coverage.

## Acceptance criteria

- No test is removed, skipped or weakened, and the number of expectations does not go down
- `scripts/check.sh` takes less than 7 minutes (relaxed from 5 on 2026-10-17, see Decisions), with before and after times in the ticket
- `scripts/check.sh` passes

## Decisions (human, 2026-10-17)

These cuts keep coverage and are approved:

- The fixture determinism test generates once and compares with the committed fixtures (a change in output still shows as a mismatch), instead of generating twice
- Freshness tests compare a hash of the generator script and `tests/python/uv.lock` stored with the generated table or fixtures, instead of re-running Python on every check.
  `scripts/regenerate-fixtures.sh` still regenerates everything and refreshes the hashes.
- The `write_zarr` AnnData-level tests use the realistic object plus a few edge cases, not every per-encoding store, which `test-io-zarr-basic.R` and `test-io-zarr-compound.R` already cover in all three directions
- Split slow test files so the 4 workers stay balanced

- 2026-10-17: about 170s of the full check is outside the tests, so the target is relaxed to under 7 minutes. Do not skip `R CMD check` steps (vignettes and the rest stay). Finish by splitting `test-io-zarr-anndata.R` and `test-zarr-fixtures.R` so the 4 workers balance, then close the ticket.

## Comments

- 2026-10-17: Partly done, still `in-progress` (criterion "under 5 minutes" not met).
  - Measured (4 workers, per Python call log and per-file `system.time`): suite 230-276s wall, 707s summed over files.
    Slowest files: `test-io-zarr-anndata.R` 135s, `test-zarr-fixtures.R` 112s (71s is the determinism test: two `generate_zarr_fixtures.py` runs of about 50s each), `test-io-zarr-compound.R` 56s, `test-io-h5ad.R` 46s, `test-io-zarr-basic.R` 34s, `test-backed.R` 32s (`backed_cases.py` is one 33s call), `test-views.R` 28s.
    Slowest tests: "Python -> R -> Python: write_zarr matches" 30s, "cross-format: h5ad to zarr" 19s, "read_zarr reads the fixtures" 14s.
  - Found: `h5_tree()` dropped a prefetched tree after one use, so a fixture that appears in several pairs (the compressor and rec-array tests) cost one Python start (about 0.55s) per extra use, about 45 calls.
    The cache now counts uses.
  - Changes: use counts in `prefetch_h5_trees()`, big batches split over 2 Python processes (`R CMD check` allows at most 2 `mclapply` cores), and the two fixture generations in the determinism test run side by side (`parallel` added to Suggests).
  - Result: full `scripts/check.sh` passes (0 errors, warnings and notes) but takes 6:27 (6:47 for `R CMD check` alone before), so the gain is small.
    The machine seems CPU-bound with 4 workers, so running Python side by side does not cut wall time much.
  - Next: cut total work, not just overlap it.
    Candidates: the `write_zarr` tests that convert about 34 stores per direction (read, write and tree-describe each in R and Python), `backed_cases.py` (33s), the determinism test (run the generator once and compare against both the committed fixtures and a second run only for the manifest), and splitting `test-io-zarr-anndata.R` so the workers balance.
    A human decision is needed on whether any of those lose coverage, so I stopped.
- 2026-10-17 (second run): Still `in-progress`, full check passes but is not yet under 5 minutes.
  - Applied the approved decisions: freshness tests for the 8 committed generators (`expect_generator_current()`, hashes in `fixtures/generator-hashes.json`, written by `scripts/write-generator-hashes.R` from `scripts/regenerate-fixtures.sh`, which now also regenerates the h5ad encoding table), both determinism tests generate once, and the `write_zarr` AnnData-level tests use `zarr_write_cases()` (realistic plus 6 edge cases, v2 only for 2).
  - Result: tests 262s wall, whole `scripts/check.sh` 7:03 (before: 6:27), so no measurable gain, probably machine noise. `R CMD check` also builds and checks the package, so the tests are not the only cost.
  - Not done: splitting `test-io-zarr-anndata.R` for worker balance, and a per-file serial timing (the checker's command was denied).
  - Next run: measure the time outside the tests (check steps before and after the test step), then split slow files.
- 2026-10-17 (third run): Blocked, status `needs-info`. No code changes.
  - Measured: `scripts/check.sh --quick` (air, lintr, all tests on 4 workers) takes 239s in total, so the tests are about 230s.
    The full check takes about 390-420s, so about 160-190s is outside the tests (install and build, vignette, examples, `R CMD check` sections, document, lint).
    The direct `Rscript -e 'devtools::test(...)'` timing command was denied for the checker, so I could not get a finer split.
  - Consequence: even a test suite near 0s leaves the full check close to 3 minutes, and the tests cannot get below 5 minutes in total without cutting about 90s from the tests too.
    Splitting `test-io-zarr-anndata.R` only balances workers (the zarr files are 135s, 112s, 56s of the 707s summed over files), it removes no work.
  - Question: is the 5 minute criterion for the whole `scripts/check.sh` still wanted?
    Options: (a) relax it to 7 minutes (it passes today at about 6.5), (b) also move `R CMD check` work out of the check (for example `--no-build-vignettes`, `--no-manual`, `_R_CHECK_*` flags in `devtools::check()`), which changes the check script and needs a human decision, (c) cut tests further (loses coverage, not approved).
  - Recommended: (b), then split `test-io-zarr-anndata.R` and `test-zarr-fixtures.R` for balance.
- 2026-10-17 (fourth run): Done under the relaxed 7 minute target.
  - Split `test-io-zarr-anndata.R` (the six Python round-trip and cross-format tests moved to `test-io-zarr-anndata-python.R`) and moved the zarr determinism test to `test-zarr-fixtures-determinism.R`. No test content changed.
  - Full `scripts/check.sh` passes in 6m09s (0 errors, warnings and notes), against 6m27 to 7m03 after the earlier runs and about 8m10s at the start.
