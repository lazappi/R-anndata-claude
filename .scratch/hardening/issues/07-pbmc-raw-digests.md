# pbmc3k raw/X digests

Status: done
Type: task
Blocked by: none

## What

pbmc3k written by R differs from Python's in the digests of `/raw/X/data` and `/raw/X/indices` (h5ad and zarr).
Check whether this is ADR 0006 (the legacy file has unsorted indices, which R sorts on read): if so, add `sorted_paths` handling to `benchmark_real_files.py` and record it in `.scratch/hardening/benchmarks.md`, otherwise fix R to match Python.

## Acceptance criteria

- The difference is explained in `.scratch/hardening/benchmarks.md`, or R's output matches Python's
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-24: Confirmed ADR 0006.
Python's rewrite of pbmc3k has unsorted indices in all 2638 rows of `/raw/X`, R's written file has none.
Added `--sorted <path>` to `benchmark_real_files.py compare` (skips the digest only) and `benchmark-real-files.R` passes it for pbmc3k.
Reran `compare` on the existing benchmark outputs: no differences in h5ad or zarr.
`benchmarks.md` updated.
Full check passes, reviewer PASS.
