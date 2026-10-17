# Backed dense X

Status: ready-for-agent
Type: task
Blocked by: 02

## What

The backed dense class: `dim()`, `[` with every R index form, conversion to a matrix, printing, On-disk dtype records, and Views of backed objects reading only their subset.

## Acceptance criteria

- The dense rows of the operations table pass, and every R index form matches the in-memory selection
- `scripts/check.sh` passes

## Comments
