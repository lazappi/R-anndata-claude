# pkgdown site

Status: done
Type: task
Blocked by: 02, 04

## What

Add `_pkgdown.yml` (reference grouped by area: core object, h5ad, zarr, backed, lazy, concat, other formats, settings and conditions, with the vignettes as articles) and build the site locally with `pkgdown::build_site()` into the git-ignored `docs/` output (keep `docs/adr/` and `docs/agents/` untouched, so set a different `destination` such as `pkgdown-site/`).
Add the config and output directory to `.Rbuildignore` and the output to `.gitignore`.
Do not deploy.

## Acceptance criteria

- `pkgdown::check_pkgdown()` passes and the site builds without warnings
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: Added `_pkgdown.yml` (destination `pkgdown-site/`, reference groups, both vignettes as articles), `.Rbuildignore` and `.gitignore` entries.
The `url` (`https://lazappi.github.io/R-anndata-claude/`) is a **placeholder** until a GitHub remote exists (human decision).
`check_pkgdown()` also requires the same URL in the `DESCRIPTION` `URL` field, so it was added there too (the placeholder applies to both, update both when the real address is known).
"Backed and lazy reading" has no separate backed page because the backed help pages are internal, so `sparse_dataset` is grouped with the lazy readers.
Build recipe: the vignettes need the package installed, so `R CMD INSTALL -l .ralph/oracle/lib .` then `Rscript -e '.libPaths(c(".ralph/oracle/lib", .libPaths())); pkgdown::build_site(preview = FALSE, install = FALSE)'`.
The only build warnings are pandoc's `--mathml`/`--mathjax` deprecation notices from the installed pandoc, not from the package.
