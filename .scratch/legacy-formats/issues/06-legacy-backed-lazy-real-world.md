# legacy-formats: backed, lazy and real-world files

Status: in-progress
Type: task
Blocked by: 05

## What

- Legacy fixtures through `read_h5ad(backed=)` and the lazy readers, following Python for what works and what errors
- Round trips: reading a legacy file then writing gives the current encodings, equivalent to Python's rewrite (`expect_python_equal()`)
- The PBMC 3k real-world test reads the original download directly, with no Python rewrite first (the Discovered item in `fix_plan.md`)
- A vignette or help page note on legacy formats and `OldFormatWarning`, and a `NEWS.md` entry

## Acceptance criteria

- Backed and lazy reads of the fixtures match the expectation table
- The real-world test no longer calls `python_rewrite_h5ad()` on the download
- Documentation is updated
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

- 2026-10-23: Python (oracle) reads all five h5ad fixtures with `backed = "r"`, but `read_lazy` only reads 0.10.9 (the 0.6.22 files raise TypeError for `raw.X`, 0.7.8 raises IORegistryError for dataframe 0.1.0) and does not move neighbors matrices to `obsp`
- `backed_x_elem()` now keeps unencoded dense and h5sparse `X` on disk (`backed_legacy_x()`, warns old format), and `read_anndata_elem()` skips `move_adjacency_matrices()` in lazy mode
- `test-io-legacy-modes.R`: backed vs in-memory reads, `read_lazy` follows Python (works for 0.10.9, errors otherwise), R-written files equal Python's rewrite (`expect_python_equal()`, h5ad and zarr)
- NOT met: the PBMC 3k test still reads the Python rewrite. Reading the original download fails with `Cannot read '/obsm', it is complex64 and only complex128 can be read.` (`read_unencoded_elem()` -> `array_read()` -> `h5_read_complex()`): `/obsm` looks like a compound dataset (a structured array of obsm fields), which Python's AnnData constructor turns into a mapping of its fields. I could not inspect the file, because the python-oracle's download (`curl`) was denied. Next run: download pbmc3k.h5ad to `.ralph/oracle/` (if allowed), inspect `/obsm`, `/varm` and `/uns` with h5py, ask the oracle for Python's path, implement it, then switch the test to read the download directly (try `quietly_read()` around `read_h5ad(download)`) and compare with the rewrite
- Docs: `io-legacy` help page and `NEWS.md` (done)
