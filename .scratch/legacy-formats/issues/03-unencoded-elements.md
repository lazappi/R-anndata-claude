# legacy-formats: unencoded Elements and h5sparse groups

Status: done
Type: task
Blocked by: 02

## What

Read Elements written without encoding metadata, as `read_basic` does (`methods.py:202-330`), in h5ad and zarr.

- Unencoded dense arrays, scalars (1-element arrays in 0.6.22, 0-d in 0.7.x) and strings, dicts, `X`, `layers`, `obsm`, `obsp` and `uns`
- h5sparse legacy attributes (`h5sparse_format`, `h5sparse_shape`) on a group, read to a CSR or CSC matrix
- `sparse_dataset()` on a group with those attributes (the `legacy_attributes` row of the backed operations table, moved here from backed/04)
- One `anndata_old_format_warning` per unencoded Element exactly where Python raises `OldFormatWarning` (the spike table lists which paths warn)
- Writing back always uses the current encodings

## Acceptance criteria

- The 0.6.22 and 0.7.8 fixtures of ticket 02 read to the values and warnings in the expectation table, for h5ad and zarr where a store exists
- `legacy_attributes` row passes for `sparse_dataset()`
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: Part done, ticket stays in-progress.

- `R/io-legacy.R` `read_unencoded_elem()` is called from `read_elem_object()` for any Element without encoding attributes: warns `anndata_old_format_warning` (field `path`), then reads a dataset like an array (1-element 1-d keeps `dim` 1, 0-d is a scalar), a group with `h5sparse_format` as CSR/CSC (`read_sparse_parts()` split out of `read_sparse_elem()`) and any other group as a dict. Works on h5ad and zarr through the new store op `is_group()`
- An unencoded root reads as an AnnData with no warning (Python's callback), but a root without `obs` keeps the `anndata_legacy_format_error`
- `sparse_dataset()` accepts h5sparse groups (`shape` preferred over `h5sparse_shape`, as Python): the `legacy_attributes` row passes (test in `test-backed-sparse.R`)
- `test-io-legacy.R` reads Elements of the 0.6.22 and 0.7.8 fixtures (h5ad and zarr) and compares values and warned paths to the table. `legacy_table()` moved to `helper-legacy.R`
- Not met yet: reading whole fixtures to the table values needs `obs`/`var` (dataframe 0.1.0 and compound datasets, ticket 04) and `raw.*` (ticket 05), so whole-file comparison is left to those tickets. Remaining here: nothing else known, so mark done once 04 and 05 let whole files read
- 2026-10-23 (ticket 06 run): tickets 04 and 05 are done and `test-io-legacy.R` compares every part of the 0.6.22, 0.7.8 and 0.10.9 fixtures (X, layers, obsm, varm, uns, obs, var, raw, obsp, warnings) to the table, and `test-io-legacy-modes.R` reads whole files. Marked done
