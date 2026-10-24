# read_zarr() memory on large stores

Status: ready-for-agent
Type: bug
Blocked by: none

## What

`read_zarr()` of the 4 GB rewritten cellxgene-vascular store (`.ralph/oracle/bench/`, from `scripts/benchmark-real-files.R`) failed with "vector memory limit of 16.0 Gb reached", where Python reads it in 11.2s.
The benchmark session also held the object read from h5ad, so first rerun the zarr read alone in a fresh R process.
If it still fails or peaks far above the in-memory size of the result, find the copies (for example the split-parts reads of int64 and uint32, or whole-array reads before subsetting) and fix them, with a test on a smaller store that checks the path no longer copies the whole array more than once.

## Acceptance criteria

- The 4 GB store reads in a fresh R process, and its time is added to `.scratch/hardening/benchmarks.md`
- The full check (`scripts/check.sh --package` and `--tests`) passes
