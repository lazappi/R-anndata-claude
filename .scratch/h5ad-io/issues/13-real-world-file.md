# Real-world file test

Status: in-progress
Type: task
Blocked by: 12

## What

Download scanpy's `pbmc3k_processed` in a test that skips offline, read it, round trip it through R and check Structural equivalence with the original.
Fix or record in `fix_plan.md` anything it finds.

## Acceptance criteria

- The test passes with network and skips cleanly without
- `scripts/check.sh` passes

## Decisions (human, 2026-10-16)

- Keep the fix in `R/io-sparse.R` that sorts unsorted indices on read, with a unit test using a small file with unsorted indices (ADR 0006).
  Compare `/raw/X` (and any other sparse Element with unsorted indices in the original) by value, not by Structural equivalence.
- Exempt `/uns/rank_genes_groups` with `rec_array_paths` and check it with `expect_rec_array_values_equal()`, as the other rec-array tests do (ADR 0005, h5ad-io/15)
- The test may download a different file from scanpy's `pbmc3k_processed` as long as the ticket comment names the source

## Comments
