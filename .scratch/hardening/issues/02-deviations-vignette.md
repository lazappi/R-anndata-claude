# Deviations vignette

Status: done
Type: task
Blocked by: none

## What

Collect every documented deviation from Python 0.13.4 (search tickets in `.scratch/*/issues/`, specs, ADRs, help pages, `NEWS.md` and `CLAUDE.md`) into `vignette("deviations")`, grouped by area, each with its reason and the ticket or ADR it comes from.
Link the vignette from the help pages that mention a deviation and from the main vignette.
If the help pages can share a marker (such as a `@section Deviations:`), add a test that every marked deviation appears in the vignette.

## Acceptance criteria

- The vignette builds and covers every deviation found
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: Added `vignettes/deviations.Rmd` grouped by area with a ticket or ADR for each entry, and linked it from the main vignette.
Marker convention: help pages with a deviation have `@section Deviations from Python:` ending with a `vignette("deviations")` link (`AnnData`, `concat`, `io-rec-array`, `lazy-dense`, `read_excel`, `read_lazy`, `read_elem_lazy`, `anndata-index`).
The vignette names each marked page as `` `?name` ``, and `test-deviations.R` checks both directions plus the link.
Adding a deviation: add the section to its help page and an entry (with the `?name` line) to the vignette.
The test cannot check that every deviation inside a page is listed, only the page.
The zarr rec-array single chunk (zarr-io/14) is listed but was not re-verified against the current code.
