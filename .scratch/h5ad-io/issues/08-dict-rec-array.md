# Dict and rec-array

Status: needs-triage
Type: task
Blocked by: 05, 06

## What

Register `dict` 0.1.0 and `rec-array` 0.2.0.

- Named lists, including nested and empty dicts, and `null` values
- Unnamed or partly named lists raise `anndata_io_registry_error`
- `rec-array` read into a marker-class `data.frame` keeping field names, order and dtypes, including fixed-length byte and unicode fields, and written back with the same compound type
- Fixtures including a scanpy `rank_genes_groups`-shaped uns

## Acceptance criteria

- All three round-trip directions pass for each fixture
- `scripts/check.sh` passes

## Comments
