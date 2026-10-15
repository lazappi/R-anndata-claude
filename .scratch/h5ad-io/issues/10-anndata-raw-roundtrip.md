# AnnData and Raw, read_h5ad and write_h5ad basics

Status: needs-triage
Type: task
Blocked by: 07, 08, 09, core-object/08

## What

Register `anndata` 0.1.0 and `raw` 0.1.0 and add `read_h5ad(filename)` and `write_h5ad(adata, filename)`, plus `adata$write_h5ad(filename)` and `adata$unwriteable(store_type = NULL)` (`anndata.py:1492-1577`).

- Root encoding attributes, always-written empty dict groups for obsm, varm, obsp, varp, layers and uns
- The `NA` layer (ADR 0004) written to `/X`, never inside `/layers`
- File with no `X` reads as `NULL`
- Raw with its own var and varm
- Empty and degenerate shapes: 0 observations, 0 variables, no X, empty Slots
- `backed` errors with "not yet supported"
- Fixtures for raw, degenerate shapes and empty Slots

## Acceptance criteria

- All three round-trip directions pass for each fixture
- `unwriteable()` is tested against Python
- `scripts/check.sh` passes

## Comments
