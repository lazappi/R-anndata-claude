# rec-array field dtype fidelity

Status: needs-triage
Type: task
Blocked by: 08

## What

Restore full `rec-array` fidelity, which the MVP gives up (ADR 0005): field dtypes (integer widths and signedness, float32, bool) and h5py's variable-length UTF-8 string fields, on both read and write, so that `rec-array` Elements are Structurally equivalent after a Round trip.

Options, to be decided when this ticket is triaged:

1. Upstream rhdf5 support for compound types (`H5Tinsert`, `H5Tget_member_type`, `H5Tget_member_name`, `H5Tget_sign`), if it has appeared since 2.57.20
2. A small compiled helper in `src/`, using `LinkingTo: Rhdf5lib`, that reads a compound type's members and creates a compound dataset from a field specification
3. `hdf5r` for `rec-array` only (needs a system libhdf5)

The same helper could also replace the fragile workarounds found by the spike (the raw buffer for booleans, `integer64` writes and complex64 reads).

## Acceptance criteria

- rec-array fixtures (`rec_array_basic`, `rec_array_widths`, `rec_array_object_field`, `rec_array_rank_genes_groups`) are Structurally equivalent after every round-trip direction
- The rec-array relaxation in the test helpers and the deviation notes in the documentation are removed
- ADR 0005 is superseded
- `scripts/check.sh` passes

## Comments
