# Fix plan

The prioritised queue for the Ralph loop (see `PROMPT.md`).
Each run takes the first unblocked item.
The loop may tick items, split them into sub-items and add Discovered and Blocked entries.
The human owns the order of the Queue.

## Queue

- [x] foundations/01: package skeleton (`.scratch/foundations/issues/01-package-skeleton.md`)
- [x] foundations/02: formatting and linting (`.scratch/foundations/issues/02-formatting-and-linting.md`)
- [x] foundations/03: check script (`.scratch/foundations/issues/03-check-script.md`)
- [x] foundations/04: condition helpers (`.scratch/foundations/issues/04-condition-helpers.md`)
- [x] foundations/05: settings (`.scratch/foundations/issues/05-settings.md`)
- [x] foundations/06: Python reference environment (`.scratch/foundations/issues/06-python-environment.md`)
- [x] foundations/07: structural comparison helpers (`.scratch/foundations/issues/07-structural-comparison.md`)
- [x] foundations/08: fixture pipeline and offline mode (`.scratch/foundations/issues/08-fixture-pipeline.md`)
- [x] Break `.scratch/core-object/spec.md` into tickets (`.scratch/core-object/issues/`, all `needs-triage`), once foundations is done (16 tickets, awaiting human triage)
- [x] Break `.scratch/h5ad-io/spec.md` into tickets (`.scratch/h5ad-io/issues/`, all `needs-triage`), once foundations is done (14 tickets, awaiting human triage)
- [ ] h5ad-io/01: rhdf5 capability spike (`.scratch/h5ad-io/issues/01-rhdf5-spike.md`) (decision made, finish the bookkeeping)
- [x] h5ad-io/02: encoding table (`.scratch/h5ad-io/issues/02-encoding-table.md`)
- [x] 🛑 Human checkpoint: review `.scratch/h5ad-io/rhdf5-spike.md` and `.scratch/h5ad-io/encoding-table.md` before core-object starts
- [ ] core-object/01: matrix value coercion and helpers (`.scratch/core-object/issues/01-matrix-values.md`)
- [ ] core-object/02: obs and var data frame handling (`.scratch/core-object/issues/02-dataframe-inputs.md`)
- [ ] core-object/03: AnnData class and basic construction (`.scratch/core-object/issues/03-anndata-class-construction.md`)
- [ ] core-object/04: X assignment and validation (`.scratch/core-object/issues/04-x-assignment.md`)
- [ ] core-object/05: aligned mappings: obsm, varm, obsp, varp (`.scratch/core-object/issues/05-aligned-mappings.md`)
- [ ] core-object/06: layers (`.scratch/core-object/issues/06-layers.md`)
- [ ] core-object/07: obs, var, names and uns assignment (`.scratch/core-object/issues/07-obs-var-names-uns-assignment.md`)
- [ ] core-object/08: raw class and raw slot (`.scratch/core-object/issues/08-raw.md`)
- [ ] core-object/09: remaining construction forms (`.scratch/core-object/issues/09-construction-forms.md`)
- [ ] core-object/10: subsetting (`.scratch/core-object/issues/10-subsetting.md`)
- [ ] core-object/11: copy and transpose (`.scratch/core-object/issues/11-copy-and-transpose.md`)
- [ ] core-object/12: obs_names_make_unique and var_names_make_unique (`.scratch/core-object/issues/12-make-unique.md`)
- [ ] core-object/13: to_df, obs_vector, var_vector and key methods (`.scratch/core-object/issues/13-data-access-methods.md`)
- [ ] core-object/14: strings_to_categoricals and rename_categories (`.scratch/core-object/issues/14-categorical-methods.md`)
- [ ] core-object/15: printing (`.scratch/core-object/issues/15-printing.md`)
- [ ] core-object/16: R generics and comparison error (`.scratch/core-object/issues/16-generics-and-comparison.md`)
- [ ] h5ad-io/03: element registry and error classes (`.scratch/h5ad-io/issues/03-element-registry.md`)
- [ ] h5ad-io/04: on-disk dtype preservation mechanism (`.scratch/h5ad-io/issues/04-on-disk-dtype-records.md`)
- [ ] h5ad-io/05: dense arrays, string arrays, scalars, null and bytes (`.scratch/h5ad-io/issues/05-dense-scalar-null.md`)
- [ ] h5ad-io/06: nullable and categorical arrays (`.scratch/h5ad-io/issues/06-nullable-categorical.md`)
- [ ] h5ad-io/07: sparse matrices (`.scratch/h5ad-io/issues/07-sparse-matrices.md`)
- [ ] h5ad-io/08: dict and rec-array (`.scratch/h5ad-io/issues/08-dict-rec-array.md`)
- [ ] h5ad-io/09: dataframe (`.scratch/h5ad-io/issues/09-dataframe.md`)
- [ ] h5ad-io/10: AnnData and Raw, read_h5ad and write_h5ad basics (`.scratch/h5ad-io/issues/10-anndata-raw-roundtrip.md`)
- [ ] h5ad-io/11: read_h5ad and write_h5ad options (`.scratch/h5ad-io/issues/11-read-write-options.md`)
- [ ] h5ad-io/12: realistic and compressed fixtures (`.scratch/h5ad-io/issues/12-realistic-fixtures.md`)
- [ ] h5ad-io/13: real-world file test (`.scratch/h5ad-io/issues/13-real-world-file.md`)
- [ ] h5ad-io/14: package vignette (`.scratch/h5ad-io/issues/14-vignette.md`)

## Discovered

- [x] `.Rbuildignore` excludes `^tests/python$`, but ticket 06 needs `tests/python` available inside `R CMD check` (tests are copied into the check directory). Fix as part of foundations/06.

## Blocked

## Follow-up

Tickets that need triage before they can be queued.

- h5ad-io/15: rec-array field dtype fidelity (`.scratch/h5ad-io/issues/15-rec-array-dtype-fidelity.md`), after the MVP
