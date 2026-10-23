# Examples for exported functions

Status: done
Type: task
Blocked by: none

## What

Give every exported function and the `AnnData()` help page runnable `@examples`, using small objects built in the example or a small h5ad shipped in `inst/extdata` (written by Python through the fixture generator).
Examples that need Python, downloads or suggested packages are wrapped so `R CMD check` still runs them where it can (`@examplesIf`).

## Acceptance criteria

- Every exported help page has examples, and they run in `R CMD check`
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: Earlier tickets had already given every exported help page runnable examples (Rarr ones use `@examplesIf`).
The only gap was `read_excel()`, whose `\dontrun` example now reads `readxl::readxl_example("datasets.xlsx")` under `@examplesIf requireNamespace("readxl")`.
No `\dontrun` or `\donttest` is left in `man/`.
Both checks and review passed.
