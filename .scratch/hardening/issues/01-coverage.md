# Coverage pass

Status: ready-for-agent
Type: task
Blocked by: none

## What

Run `scripts/check.sh --coverage`, then add tests or `# nocov` (with a reason) so every file in `R/` reaches at least 90%.
Keep it to one pass: prefer cheap tests of real behaviour, and stop rather than contrive tests for the last few lines.
Record the before and after coverage per file in the ticket comment.

## Acceptance criteria

- Every file in `R/` has at least 90% coverage, or the comment explains the shortfall
- The full check (`scripts/check.sh --package` and `--tests`) passes
