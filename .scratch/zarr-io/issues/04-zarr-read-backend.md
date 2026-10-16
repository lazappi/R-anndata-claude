# Reading zarr stores

Status: ready-for-agent
Type: task
Blocked by: 02, 03

## What

The zarr backend for reading, through Rarr (ADR 0007).

- Open a directory store, v2 or v3, consolidated or not, and walk groups, arrays and attributes
- Read arrays of every dtype, strings, scalars (shape from metadata) and sharded v3 arrays
- Apply the On-disk dtype records and the 64-bit integer policy exactly as for h5ad
- A `.zip` path raises a classed error suggesting unzipping it
- Unit tests read the zarr fixtures at this level, before any encoding

## Acceptance criteria

- Every array in the v3 and v2 fixtures reads with the right values, shape and On-disk dtype record
- `scripts/check.sh` passes

## Comments
