# Deviations vignette

Status: ready-for-agent
Type: task
Blocked by: none

## What

Collect every documented deviation from Python 0.13.4 (search tickets in `.scratch/*/issues/`, specs, ADRs, help pages, `NEWS.md` and `CLAUDE.md`) into `vignette("deviations")`, grouped by area, each with its reason and the ticket or ADR it comes from.
Link the vignette from the help pages that mention a deviation and from the main vignette.
If the help pages can share a marker (such as a `@section Deviations:`), add a test that every marked deviation appears in the vignette.

## Acceptance criteria

- The vignette builds and covers every deviation found
- The full check (`scripts/check.sh --package` and `--tests`) passes
