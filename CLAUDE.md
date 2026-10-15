## Committing

- You are allowed to commit as needed in this project
- You are allowed to acknowledge yourself on commits
- Each commit should be an atomic unit of work
- This project uses gitmoji commits, do not use conventional commits
- Keep commit messages clear and brief

## Agent skills

### Issue tracker

Issues are tracked as local markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` plus `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Specifications

- Start at `.scratch/roadmap/spec.md`, which lists the sub-projects and their order
- Python anndata 0.13.4 is the only reference, fetch it with `scripts/fetch-reference.sh` (to `.reference/anndata/`)

## Ralph loop

- Development runs as a Ralph loop: `scripts/ralph.sh` feeds `PROMPT.md` to a fresh `claude -p` run per item in `fix_plan.md`
- Loop runs use `ralph/settings.json` (Sonnet, no plugins, project subagents only, no edits to specs, ADRs or loop config)
- Project subagents are defined in `.claude/agents/`: `searcher` and `checker` (Haiku), and `python-oracle` and `reviewer` (Sonnet)
- Create a `STOP` file at the root to stop the loop after the current run
- Versions use tidyverse-style development numbers (`0.0.0.9000`), bumped by one and tagged `v<version>` only when a ticket is done

## Build, test and learnings

Kept brief and current by the loop.

- `scripts/fetch-reference.sh` fetches the Python reference to `.reference/anndata/`
- `scripts/check.sh` is the full check that must pass before every commit, and `scripts/check.sh --quick <test files>` is for use during development (`--quick` takes test file paths and lints only changed R files)
- The full check fails on any NOTE (`error_on = "note"`) and sets `_R_CHECK_SYSTEM_CLOCK_=false` itself
- `LICENSE` needs `ORGANIZATION` as well as `COPYRIGHT HOLDER`, otherwise check gives a note
- Placeholder `@importFrom` lines in `R/anndata.claude-package.R` silence the unused-Imports note, remove each once real code uses that package
- `air.toml` and `.lintr` exist, check with `air format --check .` and `lintr::lint_package()`
- `R CMD check` gives a NOTE "unable to verify current time" unless `_R_CHECK_SYSTEM_CLOCK_=false` is set, so always set it.
  Never treat a NOTE as acceptable.
- Python is only used through `uv run --project tests/python ...`
