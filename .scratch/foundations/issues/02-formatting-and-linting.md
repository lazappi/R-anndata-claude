# Formatting and linting

Status: ready-for-agent
Type: task
Blocked by: 01

## What

Configure `air` and `lintr` as described in the "Tooling" section of `.scratch/foundations/spec.md`.

- `air.toml` at the root
- `.lintr` at the root, using the default linters, with any disabled linter justified in a comment
- Both config files added to `.Rbuildignore`
- Every existing R file formatted

## Acceptance criteria

- `air format --check .` reports no changes
- `lintr::lint_package()` returns no lints
- `devtools::check()` still passes cleanly
