# concat: Views and backed inputs

Status: done
Type: task
Blocked by: 04

## What

Views and backed objects as inputs (backed read into memory, as Python does), and Structural equivalence of written results with Python's for a representative set of cases.

## Acceptance criteria

- Its rows of the concat table pass
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-22: The concat table has no View or backed rows, so `test-concat-inputs.R` covers the criteria instead: in-memory, View and backed inputs give Structurally equivalent results to each other and to Python's `concat` of the same files (`tests/python/concat_files.py`, one process for all jobs), for both axes, dense and sparse X, layers, obsm, `label`, `keys`, `index_unique` and `merge`.
The only code change was reading backed X (`layer_array()`) and backed `raw$X` (`concat_raw()`) into memory with `backed_in_memory()`, Views already worked.
`concat_files.py` takes a JSON jobs file and can be reused for more Python-side concat comparisons (ticket 06).
