# rec-array field dtype fidelity

Status: ready-for-agent
Type: task
Blocked by: 16

## What

Restore full `rec-array` fidelity, which the MVP gives up (ADR 0005): field dtypes (integer widths and signedness, float32, bool) and h5py's variable-length UTF-8 string fields, on both read and write, so that `rec-array` Elements are Structurally equivalent after a Round trip.

Options, to be decided when this ticket is triaged:

1. Upstream rhdf5 support for compound types (`H5Tinsert`, `H5Tget_member_type`, `H5Tget_member_name`, `H5Tget_sign`), if it has appeared since 2.57.20
2. A small compiled helper in `src/`, using `LinkingTo: Rhdf5lib`, that reads a compound type's members and creates a compound dataset from a field specification
3. `hdf5r` for `rec-array` only (needs a system libhdf5)

It also lifts three MVP limits from h5ad-io/08:

- string fields with non-ASCII text raise on write, because anndata decodes fixed-length strings as ASCII (variable-length UTF-8 fields fix this)
- `dataset_kwargs` (compression) is ignored for rec-arrays
- a rec-array with no rows cannot be written (rhdf5's compound writer needs a non-empty chunk)

The same helper could also replace the fragile workarounds found by the spike (the raw buffer for booleans, `integer64` writes and complex64 reads).

## Acceptance criteria

- rec-array fixtures (`rec_array_basic`, `rec_array_widths`, `rec_array_object_field`, `rec_array_rank_genes_groups`) are Structurally equivalent after every round-trip direction
- Non-ASCII rec-arrays, compressed rec-arrays and rec-arrays with no rows are written and round trip
- The rec-array relaxation in the test helpers and the deviation notes in the documentation are removed
- ADR 0005 is superseded
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Decisions (human, 2026-10-23)

- Option 2, a compiled helper linked against Rhdf5lib (ADR 0008), built in h5ad-io/16.
  Use it for every rec-array read and write in h5ad, and replace the other spike workarounds only where the helper is simpler.
- Update the rec-array section of `.scratch/h5ad-io/spec.md` is done by the orchestrator, so follow ADR 0008 here.

## Comments
