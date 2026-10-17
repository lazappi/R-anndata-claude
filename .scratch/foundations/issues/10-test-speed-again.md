# Faster test suite, again

Status: ready-for-agent
Type: task
Blocked by: none

## What

The full `scripts/check.sh` takes about 490s of its 570s time limit (`R CMD check` 6m47s with 4 test workers), so the next tests added will time out.
Speed the suite up as foundations/09 did, without testing less: measure first (inside one parallel `devtools::test()` call), batch Python calls, and share or shrink zarr and View fixtures where that loses no coverage.

## Acceptance criteria

- No test is removed, skipped or weakened, and the number of expectations does not go down
- `scripts/check.sh` takes less than 5 minutes, with before and after times in the ticket
- `scripts/check.sh` passes

## Comments
