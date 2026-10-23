# Legacy compound float32 fields

Status: ready-for-agent
Type: task
Blocked by: 16

## What

Read float32 (and any other non-float64) fields of legacy compound `obs`, `var`, `uns` and `obsm` datasets with their real types, using the helper of h5ad-io/16, and drop the `float32_obs` exemption in `test-io-real-world.R` (Discovered item from legacy-formats/06).

## Acceptance criteria

- Legacy compound fields read with their On-disk dtype records, and the PBMC test needs no float32 exemption
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments
