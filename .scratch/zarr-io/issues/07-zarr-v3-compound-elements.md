# zarr v3: nullable, categorical, dataframe, dict and rec-array Elements

Status: ready-for-agent
Type: task
Blocked by: 06

## What

Register and test the remaining encodings on zarr v3: the nullable arrays, `categorical`, `dataframe`, `dict` and `rec-array` (spec "Encodings", including the rec-array rule).

## Acceptance criteria

- All three round-trip directions pass for the v3 fixtures of these encodings
- `scripts/check.sh` passes

## Comments
