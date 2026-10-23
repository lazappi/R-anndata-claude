# Real-file benchmarks

Status: ready-for-agent
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
