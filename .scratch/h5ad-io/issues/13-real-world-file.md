# Real-world file test

Status: needs-triage
Type: task
Blocked by: 12

## What

Download scanpy's `pbmc3k_processed` in a test that skips offline, read it, round trip it through R and check Structural equivalence with the original.
Fix or record in `fix_plan.md` anything it finds.

## Acceptance criteria

- The test passes with network and skips cleanly without
- `scripts/check.sh` passes

## Comments
