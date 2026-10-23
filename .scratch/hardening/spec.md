# Hardening

Status: ready-for-agent

Sub-project 12 of the roadmap (`.scratch/roadmap/spec.md`), after every feature sub-project except `experimental`.
A clean-up pass: coverage, a single list of deviations from Python, checks on real files and user documentation.

## Decisions (human, 2026-10-23)

- Coverage: get every file to at least 90% with little effort.
  Unreachable lines (defensive aborts, platform branches) get `# nocov` with a reason instead of contrived tests, and the ticket stops at one pass rather than chasing the last percent.
- Deviations: a vignette, `vignette("deviations")`, lists every documented difference from Python 0.13.4 with its reason and a link to its ticket or ADR, and help pages link to it.
  A test checks it is complete if a clean marker convention exists (for example a `@section Deviations` in help pages).
- Real files: manual benchmarking scripts in `scripts/` (not tests, because of downloads), run on files in the git-ignored `.ralph/oracle/dl/`.
  They compare R with Python (Structural equivalence of written files) and record timings, and slow paths become new tickets.
- Docs: every exported function has runnable examples, and a pkgdown site config is built locally.
  Deploying waits for a GitHub remote.

## Required tests

- Examples run in `R CMD check`
- The deviations test (if a marker convention exists)

## Acceptance criteria

- Every ticket's criteria are met
- The full check (`scripts/check.sh --package` and `--tests`) passes
