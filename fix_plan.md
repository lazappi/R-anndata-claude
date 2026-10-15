# Fix plan

The prioritised queue for the Ralph loop (see `PROMPT.md`).
Each run takes the first unblocked item.
The loop may tick items, split them into sub-items and add Discovered and Blocked entries.
The human owns the order of the Queue.

## Queue

- [x] foundations/01: package skeleton (`.scratch/foundations/issues/01-package-skeleton.md`)
- [x] foundations/02: formatting and linting (`.scratch/foundations/issues/02-formatting-and-linting.md`)
- [x] foundations/03: check script (`.scratch/foundations/issues/03-check-script.md`)
- [ ] foundations/04: condition helpers (`.scratch/foundations/issues/04-condition-helpers.md`)
- [ ] foundations/05: settings (`.scratch/foundations/issues/05-settings.md`)
- [ ] foundations/06: Python reference environment (`.scratch/foundations/issues/06-python-environment.md`)
- [ ] foundations/07: structural comparison helpers (`.scratch/foundations/issues/07-structural-comparison.md`)
- [ ] foundations/08: fixture pipeline and offline mode (`.scratch/foundations/issues/08-fixture-pipeline.md`)
- [ ] Break `.scratch/core-object/spec.md` into tickets (`.scratch/core-object/issues/`, all `needs-triage`), once foundations is done
- [ ] Break `.scratch/h5ad-io/spec.md` into tickets (`.scratch/h5ad-io/issues/`, all `needs-triage`), once foundations is done

## Discovered

- [ ] `.Rbuildignore` excludes `^tests/python$`, but ticket 06 needs `tests/python` available inside `R CMD check` (tests are copied into the check directory). Fix as part of foundations/06.

## Blocked
