# pkgdown site

Status: ready-for-agent
Type: task
Blocked by: 02, 04

## What

Add `_pkgdown.yml` (reference grouped by area: core object, h5ad, zarr, backed, lazy, concat, other formats, settings and conditions, with the vignettes as articles) and build the site locally with `pkgdown::build_site()` into the git-ignored `docs/` output (keep `docs/adr/` and `docs/agents/` untouched, so set a different `destination` such as `pkgdown-site/`).
Add the config and output directory to `.Rbuildignore` and the output to `.gitignore`.
Do not deploy.

## Acceptance criteria

- `pkgdown::check_pkgdown()` passes and the site builds without warnings
- The full check (`scripts/check.sh --package` and `--tests`) passes
