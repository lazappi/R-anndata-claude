# Faster test suite

Status: ready-for-agent
Type: task
Blocked by: none

## What

The full `scripts/check.sh` takes about 7 minutes (`R CMD check` about 6), close to the 10-minute Bash limit that makes the checker's command go to the background.
Make the suite faster without testing less.

- Measure first: run the whole suite once with per-file timings in a single parallel `devtools::test()` call (for example with a reporter that records elapsed time per file), not file by file, because running each file separately takes more than 10 minutes.
  Record the slowest files and their times in a comment on this ticket.
- The likely main cost is the number of separate `uv run` calls, each of which starts Python and imports anndata.
  Batch several cases into one Python process where possible (for example one script call that handles a list of files, or a fixture generated once per test file instead of once per test).
- Other safe speed-ups are fine (sharing read-only fixtures within a file, avoiding repeated work in helpers).

## Acceptance criteria

- No test is removed, skipped or weakened, and no assertion is loosened.
  The number of expectations reported by the suite does not go down, and every Python round-trip direction that was checked before is still checked.
- Coverage (`scripts/check.sh --coverage`) does not go down
- `scripts/check.sh` takes less than 5 minutes, with before and after times recorded in the ticket
- `scripts/check.sh` passes

## Comments
