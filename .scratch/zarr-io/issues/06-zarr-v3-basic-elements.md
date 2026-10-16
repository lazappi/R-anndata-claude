# zarr v3: dense, string, scalar, null and sparse Elements

Status: ready-for-agent
Type: task
Blocked by: 04, 05

## What

Register and test the basic encodings on zarr v3: `array`, `string-array`, `numeric-scalar`, `string`, `null`, `csr_matrix` and `csc_matrix`, including the zarr-specific differences (spec "Encodings").

## Acceptance criteria

- All three round-trip directions pass for the v3 fixtures of these encodings
- `scripts/check.sh` passes

## Comments
