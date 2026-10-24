# Large-file performance

Status: done
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
- Run 1 (2026-10-24): profiled `read_h5ad` of the large file (`.ralph/oracle/prof-big-read.R`, about 29 s).
  93% is `read_sparse_parts`: HDF5 reads about 8 s, and the rest was an always-run `order()`/`rep.int()` for unsorted indices, `max`/`as.integer` index checks and `&`/`>=` range checks.
  Now the unsorted check only sorts when a non-increasing step is not at a slice boundary, and range/overflow checks use `min`/`max` (and skip integers), giving about 25 s (ratio about 4.3, was 5.2).
  Remaining: HDF5 reads (about 8 s), memory-bound passes over about 400M-entry index vectors (`which` on the step comparison, `as.integer`), S4 `new` validity.
  Not yet profiled on the large file: `write_h5ad` (83 s), `write_zarr` (129 s), `read_zarr` (168 s), `backed_slice`.
  `benchmarks.md` is not yet updated, wait for the final run so one benchmark rerun covers all gains.
- Run 2 (2026-10-24): profiled `write_h5ad` and `write_zarr` of the large file in separate processes (`.ralph/oracle/prof-big-write.R`, `prof-big-zarr.R write|read`).
  `write_h5ad` was 26.6 s in-process (Python 15.6 s), 12 s of it in `check_dtype_fits` (`anyNA`) and `is.na` for NaN normalisation on about 400M values.
  `check_dtype_fits()` now relies on `min`/`max` giving `NA` (no `anyNA`) and the double write only runs `is.na()` when `anyNA()`, giving 17.3 s (ratio about 1.1).
  `write_zarr` is 69 s in-process (Python 17.2 s, ratio about 4): 26% `memCompress` (Rarr gzip chunks, ours to avoid only by a different default codec), 12% `writeBin`, 11% Rarr `.truncate_overflow`, the rest dtype checks and `array`, all inside Rarr.
  `read_zarr` was not profiled (`prof-big-zarr.R read` reads `.ralph/oracle/bench/cellxgene-vascular/prof.zarr`, left by the write profile) and is for run 3, along with `benchmarks.md`.
- Run 3 (2026-10-24): `read_zarr` was 169 s, 73% in `zarr_wide_read` (int64 `indices` read as four uint16 parts through Rarr, whose chunk transposes dominate).
  Now int64/uint64 are read as two int32 parts and uint32 as one (restoring `NA` as -2^31), giving about 86 s.
  Reran `scripts/benchmark-real-files.R` for the large file and updated `benchmarks.md` (ratios: read_h5ad 5.6, write_h5ad 1.6, write_zarr 4.2, read_zarr 8.6, backed_slice 3.3).
  Not all operations are within 3x after three runs, remaining costs are in the benchmarks Notes (HDF5 reads and memory-bound passes for `read_h5ad`, Rarr internals for zarr).
  Note `report` overwrites hand-written Notes and the pbmc3k table (not rerun), they were restored by hand.
- Profile script: `.ralph/oracle/prof-write.R` (needs `.ralph/oracle/bench/pbmc3k/current.h5ad` from `scripts/benchmark-real-files.R run pbmc3k 1`).
