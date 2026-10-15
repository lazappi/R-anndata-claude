# Check script

Status: ready-for-agent
Type: task
Blocked by: 02

## What

Add `scripts/check.sh`, the single command that decides whether a ticket is done (see "Tooling" in `.scratch/foundations/spec.md`).
It runs, in order, and stops with a non-zero exit at the first failure:

1. `air format --check .`
2. `lintr::lint_package()`, failing if any lints are found
3. `devtools::document()`, then failing if any file under `man/` or `NAMESPACE` changed
4. `devtools::check()`, failing on any error, warning or note.
   Set `_R_CHECK_SYSTEM_CLOCK_=false` so the time-server check cannot produce a note.
5. A `covr::package_coverage()` report (printed only, not enforced yet)

The output should make clear which step failed.

`scripts/check.sh --quick [test files...]` is a fast mode for use during development.
It runs `air format --check`, `lintr` on changed R files and `devtools::test()` restricted to the given test files (or all tests if none are given), skipping `R CMD check` and coverage.

## Acceptance criteria

- `scripts/check.sh` and `scripts/check.sh --quick` pass on the current package
- Each step demonstrably fails the script when broken (e.g. an unformatted file, a lint or an undocumented change).
  Check this manually and describe it in the commit message, without committing the breakage.
- Usage is documented in a short comment at the top of the script
