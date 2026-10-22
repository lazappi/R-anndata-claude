# legacy-formats: backed, lazy and real-world files

Status: needs-triage
Type: task
Blocked by: 05

## What

- Legacy fixtures through `read_h5ad(backed=)` and the lazy readers, following Python for what works and what errors
- Round trips: reading a legacy file then writing gives the current encodings, equivalent to Python's rewrite (`expect_python_equal()`)
- The PBMC 3k real-world test reads the original download directly, with no Python rewrite first (the Discovered item in `fix_plan.md`)
- A vignette or help page note on legacy formats and `OldFormatWarning`, and a `NEWS.md` entry

## Acceptance criteria

- Backed and lazy reads of the fixtures match the expectation table
- The real-world test no longer calls `python_rewrite_h5ad()` on the download
- Documentation is updated
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments
