# Faster test suite, again

Status: needs-info
Type: task
Blocked by: none

## What

The full `scripts/check.sh` takes about 490s of its 570s time limit (`R CMD check` 6m47s with 4 test workers), so the next tests added will time out.
Speed the suite up as foundations/09 did, without testing less: measure first (inside one parallel `devtools::test()` call), batch Python calls, and share or shrink zarr and View fixtures where that loses no coverage.

## Acceptance criteria

- No test is removed, skipped or weakened, and the number of expectations does not go down
- `scripts/check.sh` takes less than 5 minutes, with before and after times in the ticket
- `scripts/check.sh` passes

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
