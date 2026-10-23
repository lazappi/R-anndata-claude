# Examples for exported functions

Status: ready-for-agent
Type: task
Blocked by: none

## What

Give every exported function and the `AnnData()` help page runnable `@examples`, using small objects built in the example or a small h5ad shipped in `inst/extdata` (written by Python through the fixture generator).
Examples that need Python, downloads or suggested packages are wrapped so `R CMD check` still runs them where it can (`@examplesIf`).

## Acceptance criteria

- Every exported help page has examples, and they run in `R CMD check`
- The full check (`scripts/check.sh --package` and `--tests`) passes
