# Dict and rec-array

Status: ready-for-agent
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

## Decisions (human, 2026-10-15)

- rec-array follows the updated spec section and ADR 0005: names, order and values round trip, field dtypes do not.
  Write with rhdf5's compound writer, sizing fixed-length string fields to the longest value in bytes.
- Round-trip tests compare field values in every direction (Python → R → Python with Python's own comparison of the field values), with an explicit, narrowly scoped relaxation of Structural equivalence for rec-array field types
- Document the deviation in the help pages

## Comments
