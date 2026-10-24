# read_zarr() memory on large stores

Status: done
Type: bug
Blocked by: none

## What

`read_zarr()` of the 4 GB rewritten cellxgene-vascular store (`.ralph/oracle/bench/`, from `scripts/benchmark-real-files.R`) failed with "vector memory limit of 16.0 Gb reached", where Python reads it in 11.2s.
The benchmark session also held the object read from h5ad, so first rerun the zarr read alone in a fresh R process.
If it still fails or peaks far above the in-memory size of the result, find the copies (for example the split-parts reads of int64 and uint32, or whole-array reads before subsetting) and fix them, with a test on a smaller store that checks the path no longer copies the whole array more than once.

## Acceptance criteria

- The 4 GB store reads in a fresh R process, and its time is added to `.scratch/hardening/benchmarks.md`
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

- 2026-10-24: Reran `read_zarr()` of the 4 GB store alone in a fresh R process: it succeeds in 167.97 s (user 90 s, system 63 s), giving a 1.9 Gb X, so the earlier failure came from the benchmark session holding the h5ad object. No copies to fix. Peak memory was not measured (`/usr/bin/time -l` is denied in loop runs). The benchmark script now frees the object before the zarr read, `benchmarks.md` has the time, and the 15x ratio against Python is left to hardening/08.
