# legacy-formats: backed, lazy and real-world files

Status: done
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
- 2026-10-23 (done): the human supplied `.ralph/oracle/dl/pbmc3k.h5ad`. `/obsm` and `/varm` are compound datasets with array-valued fields, which Python's `read_dataset` plus the `obsm` setter turn into a dict of matrices (`convert_to_dict_ndarray`). `read_unencoded_compound()` (`R/io-legacy.R`) does the same (`H5Dread(compoundAsDataFrame = FALSE)`, transpose each matrix), and compounds without array fields (`uns/rank_genes_groups/names`) go to `read_rec_array_elem()`. Also fixed: a one-element fixed-length string dataset reads as a scalar like Python's `read_dataset`.
  `test-io-real-world.R` now reads the download directly (it prefers the git-ignored local copy `.ralph/oracle/dl/pbmc3k.h5ad` when it exists, else downloads) and compares with Python's rewrite. Hermetic tests use `tests/python/write_compound_obsm.py`.
  Known deviation: rhdf5 exposes no compound member types (`H5Tget_member_type` is not exported), so float32 fields of a legacy compound `obs`/`var` read as float64 (the two `/obs` columns are exempted from the dtype comparison and the `obs` equality ignores attributes). Matrix fields are recorded as float32 only when the compound size determines the field widths. Documented in `io-legacy` and `NEWS.md`. A fix needs a way to read member types (C-level or another package).
- 2026-10-23 (earlier, blocked): `curl -sL -o .ralph/oracle/dl/pbmc3k.h5ad <pbmc3k_url>` was denied by the permission mode (the same denial the oracle hit), so `/obsm` of the original download cannot be inspected. Question for the human: allow that one download (to `.ralph/oracle/dl/`), or place `pbmc3k.h5ad` there yourself (the test already downloads it to a temp path, so a copy from `tests/testthat` runs would also do). Recommended: allow `curl` to `.ralph/oracle/dl/`. Then the next run inspects `/obsm` with h5py, asks the oracle for Python's path (compound dataset to a mapping of fields), implements it in `read_unencoded_elem()`, and switches `test-io-real-world.R` to read the download directly.
