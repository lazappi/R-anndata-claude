# pbmc3k raw/X digests

Status: ready-for-agent
Type: task
Blocked by: none

## What

pbmc3k written by R differs from Python's in the digests of `/raw/X/data` and `/raw/X/indices` (h5ad and zarr).
Check whether this is ADR 0006 (the legacy file has unsorted indices, which R sorts on read): if so, add `sorted_paths` handling to `benchmark_real_files.py` and record it in `.scratch/hardening/benchmarks.md`, otherwise fix R to match Python.

## Acceptance criteria

- The difference is explained in `.scratch/hardening/benchmarks.md`, or R's output matches Python's
- The full check (`scripts/check.sh --package` and `--tests`) passes
