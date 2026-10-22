# legacy-formats: unencoded Elements and h5sparse groups

Status: ready-for-agent
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
