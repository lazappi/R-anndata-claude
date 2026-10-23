# Real-file benchmarks

Date: 2026-10-23
Machine: Darwin 25.6.0 (x86_64)
Versions: R 4.6.1, anndata.claude 0.0.5.9002, rhdf5 2.57.20, Python anndata 0.13.4

Made by `scripts/benchmark-real-files.R`.
Times are the best wall-clock seconds of the repeats, on the file after a Python rewrite (the downloads are legacy format).
`backed_slice` reads the first 100 rows of a backed X, `lazy_subset` is `read_lazy()` then the first 100 observations realised.
Ratio is R time over Python time, and more than 3 is queued under Discovered in `fix_plan.md`.

## cellxgene-vascular

4034.5 MB rewritten, 83651 observations, best of 1

| Operation | R (s) | Python (s) | Ratio |
|---|---|---|---|
| `read_h5ad` | 30.52 | 5.84 | 5.2 |
| `write_h5ad` | 83.06 | 15.63 | 5.3 |
| `write_zarr` | 128.88 | 17.26 | 7.5 |
| `read_zarr` | failed | 11.18 | - |
| `backed_slice` | 1.76 | 0.44 | 4.0 |
| `lazy_subset` | 2.20 | 0.98 | 2.2 |

Structural equivalence of R's file with Python's:

- h5ad: equivalent
- zarr: equivalent

Errors:

- read_zarr: vector memory limit of 16.0 Gb reached, see mem.maxVSize()

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

- h5ad: 2 differences
  - /raw/X/data: digest differs ('7e1af05a18ba41694eecfda2801f1044a088600b09af13b814beab8405f0eb10' vs 'c73425b2e88d5d54845b08aba5ea6a382bdae30f7c3c153875018b4268d84bff')
  - /raw/X/indices: digest differs ('660f3ae44518041db5cb5169e412a567745f00e3428e5b99cac18aff1515d027' vs 'fb0af952e7852b16df7e64e87b95cafa3dd435981aed0705858b9c2bdd6a7ab1')
- zarr: 2 differences
  - /raw/X/data: digest differs ('7e1af05a18ba41694eecfda2801f1044a088600b09af13b814beab8405f0eb10' vs 'c73425b2e88d5d54845b08aba5ea6a382bdae30f7c3c153875018b4268d84bff')
  - /raw/X/indices: digest differs ('660f3ae44518041db5cb5169e412a567745f00e3428e5b99cac18aff1515d027' vs 'fb0af952e7852b16df7e64e87b95cafa3dd435981aed0705858b9c2bdd6a7ab1')

## Notes

Added by hand, so rerunning `report` overwrites them.

- Both downloads are legacy format, so each was rewritten by Python first.
  The sizes above are the rewritten files (no compression), the cellxgene download is 764 MB.
- The two `/raw/X` digest differences are the sparse `data` and `indices` of the pbmc3k raw matrix only, in both formats.
  This looks like the unsorted-indices case of ADR 0006 (the tests skip these digests with `sorted_paths`), but the cause was not confirmed.
- `read_zarr` of the cellxgene store failed in R with "vector memory limit of 16.0 Gb reached" while the R session also held the AnnData read from h5ad, so it may not fail on its own.
- Only one repeat of the large file was run, and timings are noisy at that count.

