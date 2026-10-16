# Backend-neutral store layer

Status: ready-for-agent
Type: task
Blocked by: none

## What

Decide whether the element registry gains a backend-neutral store layer so that encodings serve both HDF5 and zarr (the spec leaves this to the agents, and the spike recommends one in its "Store abstraction" section), and if so build it with HDF5 as its first backend.

- Encodings stop calling rhdf5 directly
- Reading an array takes an optional selection (row and column slices), even though zarr-io only reads whole arrays, because `backed` and `lazy` will read slices from both HDF5 and zarr (rhdf5 and Rarr both support it)
- No behaviour change: every existing h5ad test passes unchanged
- If you decide against a shared layer, record why in a comment and describe how zarr encodings will reuse the existing ones

## Acceptance criteria

- h5ad behaviour, files and tests are unchanged
- The decision and the layer's shape are recorded in a ticket comment and in `CLAUDE.md`
- `scripts/check.sh` passes

## Comments
