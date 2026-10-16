# Package vignette

Status: needs-info
Type: task
Blocked by: 12, core-object/16

## What

Write `vignettes/anndata-claude.Rmd` covering creating an `AnnData`, assigning Slots, subsetting, writing and reading h5ad, and moving a file to Python and back.
Code that needs Python is shown but not evaluated.
Add the vignette build dependencies without causing a check NOTE.

## Acceptance criteria

- The vignette builds under `scripts/check.sh` with no NOTE
- Every exported function from this sub-project is documented
- The coverage target for the MVP is met

## Comments

2026-10-16: Blocked on the build environment.
`vignettes/anndata-claude.Rmd` was written and its R chunks knit without error, but `pandoc` is not installed, so `R CMD build` fails with "Pandoc is required to build R Markdown vignettes but not available" and `scripts/check.sh` cannot pass.
Also needed: `VignetteBuilder: knitr` in `DESCRIPTION` (knitr and rmarkdown are already in Suggests), otherwise check gives a WARNING and a NOTE.
Question: install pandoc (e.g. `brew install pandoc`), or switch to a pandoc-free engine such as `litedown` (a new dependency, not covered by the spec)?
Recommended: install pandoc.
The work is in `git stash` named "h5ad-io/14: vignette" (the vignette file and the `DESCRIPTION` change).
Not done yet: coverage check (`scripts/check.sh --coverage`, target 90%) and the exported-function documentation audit.
