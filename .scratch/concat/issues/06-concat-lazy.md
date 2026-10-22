# concat: lazy inputs

Status: ready-for-agent
Type: task
Blocked by: 05

## What

Lazily read objects as inputs, kept lazy as Python does, with realised values equal to the in-memory result.
If a case cannot sensibly match Python, record it as a deviation in the ticket and the help page rather than blocking.

## Acceptance criteria

- Its rows of the concat table pass
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments
