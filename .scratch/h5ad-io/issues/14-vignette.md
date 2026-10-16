# Package vignette

Status: in-progress
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

## Decisions (human, 2026-10-16)

- pandoc is now installed (`/usr/local/bin/pandoc`), so keep R Markdown with knitr and add `VignetteBuilder: knitr`
- Restore the earlier work with `git stash pop` (stash "h5ad-io/14: vignette") and finish the ticket

## Comments

2026-10-16: Blocked on the build environment.
`vignettes/anndata-claude.Rmd` was written and its R chunks knit without error, but `pandoc` is not installed, so `R CMD build` fails with "Pandoc is required to build R Markdown vignettes but not available" and `scripts/check.sh` cannot pass.
Also needed: `VignetteBuilder: knitr` in `DESCRIPTION` (knitr and rmarkdown are already in Suggests), otherwise check gives a WARNING and a NOTE.
Question: install pandoc (e.g. `brew install pandoc`), or switch to a pandoc-free engine such as `litedown` (a new dependency, not covered by the spec)?
Recommended: install pandoc.
The work is in `git stash` named "h5ad-io/14: vignette" (the vignette file and the `DESCRIPTION` change).
2026-10-16 (later run): popped the stash, added `python.reticulate = FALSE` to the Python chunk (knitr otherwise needs reticulate even with `eval = FALSE`).
Full `scripts/check.sh` passes with no NOTE, and reviewer passed the vignette, `DESCRIPTION` and docs parts.
All 7 exports are documented.
Coverage is 83.11% (target 90%), so the ticket stays `in-progress`.
Lowest: `R/io-values-mapping.R` 0%, `R/io-sparse.R` 11.8%, `R/io-values-categorical.R` 19%, though their tests run (no skips).
Suspected cause: encodings register their functions in the registry at top level, and covr instruments the namespace copies, so the registry calls uninstrumented originals.
Next run: confirm that, then fix the measurement (e.g. look functions up by name at call time) or add tests, and re-measure before setting `done` and bumping the version.

(Earlier note) Not done yet: coverage check (`scripts/check.sh --coverage`, target 90%) and the exported-function documentation audit.
