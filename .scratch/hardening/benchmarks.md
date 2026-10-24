# Real-file benchmarks

Date: 2026-10-24
Machine: Darwin 25.6.0 (x86_64)
Versions: R 4.6.1, anndata.claude 0.0.5.9007, rhdf5 2.57.20, Python anndata 0.13.4

Made by `scripts/benchmark-real-files.R`.
Times are the best wall-clock seconds of the repeats, on the file after a Python rewrite (the downloads are legacy format).
`backed_slice` reads the first 100 rows of a backed X, `lazy_subset` is `read_lazy()` then the first 100 observations realised.
Ratio is R time over Python time, and more than 3 is queued under Discovered in `fix_plan.md`.

## cellxgene-vascular

4034.5 MB rewritten, 83651 observations, best of 1

| Operation | R (s) | Python (s) | Ratio |
|---|---|---|---|
| `read_h5ad` | 32.71 | 5.80 | 5.6 |
| `write_h5ad` | 24.32 | 15.30 | 1.6 |
| `write_zarr` | 68.59 | 16.18 | 4.2 |
| `read_zarr` | 86.18 | 10.02 | 8.6 |
| `backed_slice` | 1.72 | 0.52 | 3.3 |
| `lazy_subset` | 1.92 | 0.90 | 2.1 |

Structural equivalence of R's file with Python's:

- h5ad: equivalent
- zarr: equivalent

## pbmc3k

40.2 MB rewritten, 2638 observations, best of 3

| Operation | R (s) | Python (s) | Ratio |
|---|---|---|---|
| `read_h5ad` | 0.51 | 0.09 | 5.8 |
| `write_h5ad` | 0.84 | 0.09 | 9.1 |
| `write_zarr` | 2.09 | 0.71 | 2.9 |
| `read_zarr` | 1.11 | 0.13 | 8.4 |
| `backed_slice` | 0.30 | 0.05 | 6.2 |
| `lazy_subset` | 0.51 | 0.13 | 3.9 |

Structural equivalence of R's file with Python's:

- h5ad: equivalent (digests of `/raw/X/data` and `/raw/X/indices` skipped, see Notes)
- zarr: equivalent (same two digests skipped)

## Notes

Added by hand, so rerunning `report` overwrites them.
The pbmc3k table is from 2026-10-23 (before hardening/08), only the cellxgene-vascular table was rerun on 2026-10-24.

- Both downloads are legacy format, so each was rewritten by Python first.
  The sizes above are the rewritten files (no compression), the cellxgene download is 764 MB.
- The two `/raw/X` digest differences are the sparse `data` and `indices` of the pbmc3k raw matrix only, in both formats.
  Confirmed as the unsorted-indices case of ADR 0006: in Python's rewrite of pbmc3k all 2638 rows of `/raw/X` have unsorted indices, in R's written file none do.
  `benchmark_real_files.py compare` takes `--sorted <path>` to skip those digests, and the script passes it for pbmc3k only.
- Only one repeat of the large file was run, and timings are noisy at that count.
- After hardening/08 (three runs) the large-file ratios are `read_h5ad` 5.6 (was 5.2), `write_h5ad` 1.6 (was 5.3), `write_zarr` 4.2 (was 7.5), `read_zarr` 8.6 (was 15.0), `backed_slice` 3.3 (was 4.0).
  Remaining costs:
  - `read_h5ad`: about 8 s of HDF5 reads, the rest memory-bound passes over about 400M-entry index vectors and S4 validity
  - `write_zarr`: mostly inside Rarr (gzip `memCompress` 26%, `writeBin` 12%, `.truncate_overflow` 11%)
  - `read_zarr`: Rarr's chunk reading and transposes, and our assembly of int64 indices from two int32 parts (was four uint16 parts)

