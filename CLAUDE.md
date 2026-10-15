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
