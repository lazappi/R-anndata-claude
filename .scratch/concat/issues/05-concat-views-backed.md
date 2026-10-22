# concat: Views and backed inputs

Status: ready-for-agent
Type: task
Blocked by: 04

## What

Views and backed objects as inputs (backed read into memory, as Python does), and Structural equivalence of written results with Python's for a representative set of cases.

## Acceptance criteria

- Its rows of the concat table pass
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments
