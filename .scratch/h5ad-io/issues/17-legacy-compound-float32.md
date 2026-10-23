# Legacy compound float32 fields

Status: done
Type: task
Blocked by: 16

## What

Read float32 (and any other non-float64) fields of legacy compound `obs`, `var`, `uns` and `obsm` datasets with their real types, using the helper of h5ad-io/16, and drop the `float32_obs` exemption in `test-io-real-world.R` (Discovered item from legacy-formats/06).

## Acceptance criteria

- Legacy compound fields read with their On-disk dtype records, and the PBMC test needs no float32 exemption
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: `read_dataframe_legacy()` now reads with `table_read(records = TRUE)` (string records dropped from columns) and `read_unencoded_compound()` records every numeric field from `compound_members()`, replacing the size-based `compound_float_widths()` guess and the int64 rhdf5 probe (`table_int64_fields()` removed as dead code).
The PBMC test keeps only the `rank_genes_groups` rec-array exemption (fixed-length strings, not float32).
New test checks 0.6.22 `obs`/`var` dtype records against the helper, and the `ambiguous` uns field now gets float32.
