# Package skeleton

Status: ready-for-agent
Type: task
Blocked by: none

## What

Create the `anndata.claude` package skeleton at the repository root with usethis, following the "Package skeleton" section of `.scratch/foundations/spec.md`.

- `DESCRIPTION` with the metadata, Imports and Suggests listed in the spec
- `LICENSE` and `LICENSE.md` (BSD-3-Clause), acknowledging the Python anndata authors
- `README.md` stating the goal and the relationship to Python anndata 0.13.4
- `Version: 0.0.0.9000` (tidyverse-style development version, see `CLAUDE.md`)
- `.Rbuildignore` excluding every non-package file and directory (`.scratch`, `.reference`, `.remember`, `.ralph`, `.claude`, `ralph`, `docs`, `scripts`, `CONTEXT.md`, `CLAUDE.md`, `PROMPT.md`, `fix_plan.md` and any others present)
- `.gitignore` additions for R artefacts
- testthat 3e set up, with one placeholder test that passes
- Package-level documentation (`anndata.claude-package`) generated with roxygen2

## Acceptance criteria

- `devtools::check()` passes with 0 errors, 0 warnings and 0 notes
- `devtools::test()` passes
- No exported functions yet apart from package documentation

## References

- `.scratch/foundations/spec.md` (Package skeleton)
- ADR 0001
