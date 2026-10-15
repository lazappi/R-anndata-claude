# Package vignette

Status: needs-triage
Type: task
Blocked by: 12

## What

Write `vignettes/anndata-claude.Rmd` covering creating an `AnnData`, assigning Slots, subsetting, writing and reading h5ad, and moving a file to Python and back.
Code that needs Python is shown but not evaluated.
Add the vignette build dependencies without causing a check NOTE.

## Acceptance criteria

- The vignette builds under `scripts/check.sh` with no NOTE
- Every exported function from this sub-project is documented
- The coverage target for the MVP is met

## Comments
