# Large-file performance

Status: ready-for-agent
Type: task
Blocked by: 06

## What

Profile `write_h5ad()`, `read_h5ad()`, `write_zarr()` and backed slicing on the large file (`cellxgene-vascular` in `.ralph/oracle/bench/`, rewritten by `scripts/benchmark-real-files.R`), not pbmc3k, whose times are mostly fixed overhead.
Fix the biggest costs in order, aiming for within 3x of Python on the large file (see `.scratch/hardening/benchmarks.md` and the progress notes in `fix_plan.md`).
Time-boxed: take at most three runs, committing each gain that passes the full check, and record what remains and why in the comment.
Keep each profiling command under the 10-minute limit (profile one operation per process).

## Acceptance criteria

- `.scratch/hardening/benchmarks.md` has updated large-file times
- Either every operation is within 3x of Python, or the comment records the remaining costs after three runs
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

Notes carried over from fix_plan.md (pbmc3k profiling, 2026-10-23):

- Progress (2026-10-23): `check_dtype_fits()` was 40-50% of pbmc3k `write_h5ad`, now has min/max fast paths (pbmc3k write about 0.74s to 0.57s in-process).
- Still to do: `aperm` and `.Call` (H5Dwrite) in `write_dataset`, `attr_write` per-attribute overhead (about 10%), and on read `aperm.default`, `h5_info`/`h5ls` calls (13%), S4 `new_sparse_matrix` validity.
- Profile script: `.ralph/oracle/prof-write.R` (needs `.ralph/oracle/bench/pbmc3k/current.h5ad` from `scripts/benchmark-real-files.R run pbmc3k 1`).
