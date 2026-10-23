# Real-file benchmarks

Status: done
Type: task
Blocked by: none

## What

Write `scripts/benchmark-real-files.R` (with a Python counterpart run through `uv run --project tests/python`) that, for each h5ad in `.ralph/oracle/dl/` (`pbmc3k.h5ad`, about 3k cells, and `cellxgene-vascular.h5ad`, 84k cells and 800 MB), times R and Python on:

- `read_h5ad()` and `write_h5ad()`
- `write_zarr()` and `read_zarr()`
- backed mode (`backed = "r"`) reading a slice of X
- `read_lazy()` and realising a subset

Check that files written by R are Structurally equivalent to Python's (current-format files only, rewrite legacy downloads first), and write the results to `.scratch/hardening/benchmarks.md` with the machine, versions and date.
Downloads are not allowed in loop runs, so use only those files and stop to record a blocker if one is missing.
Any operation more than three times slower than Python, or that fails, becomes an item under Discovered in `fix_plan.md` with its numbers.
Never run the large file inside the 10-minute check, and run each benchmark as its own command.

## Acceptance criteria

- `.scratch/hardening/benchmarks.md` records every operation for both files
- Slow or failing operations are queued in `fix_plan.md`
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: Added `scripts/benchmark-real-files.R` (`run <name> <repeats>` per file, then `report`) and `tests/python/benchmark_real_files.py` (`time` and `compare` subcommands).
Results are in `.scratch/hardening/benchmarks.md`, raw JSON in the git-ignored `.ralph/oracle/bench/`.
Both downloads are legacy format, so the script rewrites them with Python first.
R was 2.2 to 9.1 times slower than Python on every operation that finished and `read_zarr` of the large store failed with the 16 GB vector memory limit, all queued under Discovered in `fix_plan.md`.
Written files are Structurally equivalent except two `/raw/X` digests of pbmc3k (probably ADR 0006 unsorted indices, unconfirmed).
The large file took about 6 minutes for one run of the script, so keep it as its own command.
