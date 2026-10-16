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
- [x] h5ad-io/01: rhdf5 capability spike (`.scratch/h5ad-io/issues/01-rhdf5-spike.md`)
- [x] h5ad-io/02: encoding table (`.scratch/h5ad-io/issues/02-encoding-table.md`)
- [x] 🛑 Human checkpoint: review `.scratch/h5ad-io/rhdf5-spike.md` and `.scratch/h5ad-io/encoding-table.md` before core-object starts
- [x] core-object/01: matrix value coercion and helpers (`.scratch/core-object/issues/01-matrix-values.md`)
- [x] core-object/02: obs and var data frame handling (`.scratch/core-object/issues/02-dataframe-inputs.md`)
- [x] core-object/03: AnnData class and basic construction (`.scratch/core-object/issues/03-anndata-class-construction.md`)
- [x] core-object/04: X assignment and validation (`.scratch/core-object/issues/04-x-assignment.md`)
  - [x] `X` setter rules (scalar, reshape, 3-D, NULL)
  - [x] `adata$layers[[NA]]` assignment, once ticket 06 provides layers
- [x] core-object/05: aligned mappings: obsm, varm, obsp, varp (`.scratch/core-object/issues/05-aligned-mappings.md`)
- [x] core-object/06: layers (`.scratch/core-object/issues/06-layers.md`)
- [x] core-object/07: obs, var, names and uns assignment (`.scratch/core-object/issues/07-obs-var-names-uns-assignment.md`)
- [x] core-object/08: raw class and raw slot (`.scratch/core-object/issues/08-raw.md`)
- [x] core-object/09: remaining construction forms (`.scratch/core-object/issues/09-construction-forms.md`)
- [x] core-object/10: subsetting (`.scratch/core-object/issues/10-subsetting.md`)
- [x] core-object/11: copy and transpose (`.scratch/core-object/issues/11-copy-and-transpose.md`)
- [x] core-object/12: obs_names_make_unique and var_names_make_unique (`.scratch/core-object/issues/12-make-unique.md`)
- [x] core-object/13: to_df, obs_vector, var_vector and key methods (`.scratch/core-object/issues/13-data-access-methods.md`)
- [x] core-object/14: strings_to_categoricals and rename_categories (`.scratch/core-object/issues/14-categorical-methods.md`)
  - [x] `strings_to_categoricals` and `rename_categories` on obs and var
  - [x] `rename_categories` renaming of scanpy `uns` rec-array fields (needs rec-array structure from h5ad-io/08)
- [x] core-object/15: printing (`.scratch/core-object/issues/15-printing.md`)
- [x] core-object/16: R generics and comparison error (`.scratch/core-object/issues/16-generics-and-comparison.md`)
- [x] h5ad-io/03: element registry and error classes (`.scratch/h5ad-io/issues/03-element-registry.md`)
- [x] h5ad-io/04: on-disk dtype preservation mechanism (`.scratch/h5ad-io/issues/04-on-disk-dtype-records.md`)
- [x] h5ad-io/05: dense arrays, string arrays, scalars, null and bytes (`.scratch/h5ad-io/issues/05-dense-scalar-null.md`)
- [x] h5ad-io/06: nullable and categorical arrays (`.scratch/h5ad-io/issues/06-nullable-categorical.md`)
- [x] h5ad-io/07: sparse matrices (`.scratch/h5ad-io/issues/07-sparse-matrices.md`)
- [x] foundations/09: faster test suite (`.scratch/foundations/issues/09-test-speed.md`)
- [x] core-object/17: deprecation warnings (`.scratch/core-object/issues/17-deprecation-warnings.md`)
- [x] core-object/18: escape keys in printing like Python's repr (`.scratch/core-object/issues/18-repr-key-escaping.md`)
- [x] h5ad-io/08: dict and rec-array (`.scratch/h5ad-io/issues/08-dict-rec-array.md`)
- [x] h5ad-io/09: dataframe (`.scratch/h5ad-io/issues/09-dataframe.md`)
- [x] h5ad-io/10: AnnData and Raw, read_h5ad and write_h5ad basics (`.scratch/h5ad-io/issues/10-anndata-raw-roundtrip.md`)
- [x] h5ad-io/11: read_h5ad and write_h5ad options (`.scratch/h5ad-io/issues/11-read-write-options.md`)
- [x] h5ad-io/12: realistic and compressed fixtures (`.scratch/h5ad-io/issues/12-realistic-fixtures.md`)
- [x] h5ad-io/13: real-world file test (`.scratch/h5ad-io/issues/13-real-world-file.md`)
- [x] h5ad-io/14: package vignette (`.scratch/h5ad-io/issues/14-vignette.md`)
- [x] zarr-io/01: zarr library spike (`.scratch/zarr-io/issues/01-zarr-library-spike.md`), re-run against Rarr devel and zarr main (see Decisions)
- [x] 🛑 Human checkpoint: review `.scratch/zarr-io/zarr-spike.md`, then grill the rest of the zarr-io spec and write its tickets
- [x] zarr-io/02: backend-neutral store layer (`.scratch/zarr-io/issues/02-store-abstraction.md`)
- [x] zarr-io/03: zarr fixtures and encoding table (`.scratch/zarr-io/issues/03-zarr-fixtures-and-encoding-table.md`)
- [x] zarr-io/04: reading zarr stores (`.scratch/zarr-io/issues/04-zarr-read-backend.md`)
- [x] zarr-io/05: writing zarr stores (`.scratch/zarr-io/issues/05-zarr-write-backend.md`)
- [ ] zarr-io/06: zarr v3 dense, string, scalar, null and sparse Elements (`.scratch/zarr-io/issues/06-zarr-v3-basic-elements.md`)
- [ ] zarr-io/07: zarr v3 nullable, categorical, dataframe, dict and rec-array Elements (`.scratch/zarr-io/issues/07-zarr-v3-compound-elements.md`)
- [ ] zarr-io/08: read_zarr, write_zarr and settings (`.scratch/zarr-io/issues/08-read-write-zarr.md`)
- [ ] zarr-io/09: writing sharded zarr v3 (`.scratch/zarr-io/issues/09-zarr-shard-writing.md`)
- [ ] zarr-io/10: reading zarr v2 (`.scratch/zarr-io/issues/10-zarr-v2-read.md`)
- [ ] zarr-io/11: writing zarr v2 (`.scratch/zarr-io/issues/11-zarr-v2-write.md`)
- [ ] zarr-io/12: zarr documentation (`.scratch/zarr-io/issues/12-zarr-docs.md`)

## Discovered

- [x] `.Rbuildignore` excludes `^tests/python$`, but ticket 06 needs `tests/python` available inside `R CMD check` (tests are copied into the check directory). Fix as part of foundations/06.

- [x] Deadlock: core-object/06 has `Blocked by: 04`, but 04's last sub-item (`layers[[NA]]` assignment) needs 06. The human should remove 04 from 06's `Blocked by:` (06 can then finish 04's sub-item).

- [x] Python 0.13.4 marks `obs_vector`, `var_vector` and the `*_keys()` methods deprecated (they warn). core-object/13 does not warn, because the spec is silent. The human should decide whether to add an `anndata_deprecated_warning`.

- [x] rec-arrays ignore `dataset_kwargs` (compression, ticket h5ad-io/11) and a rec-array with no rows cannot be written, because rhdf5's compound writer needs a non-empty chunk (h5ad-io/15 would fix both)

- [x] `format.AnnData` does not escape control characters in keys as Python's `repr` does (`\n`, `\t`), see `quote_key()` in `R/printing.R`

- [ ] The cellxgene PBMC 3k file (the real-world test download) is in a legacy format that `read_h5ad()` rejects (`anndata_legacy_format_error`, unencoded root Element), so the test reads a Python rewrite of it, reading the original needs the `legacy-formats` sub-project

- [x] Coverage was understated because the registry held uninstrumented function copies under covr, fixed with `late_bound()`, now 96.42%

- [ ] Python writes a missing `raw` as a `null` Element in zarr (not in h5ad), and zarr keeps rec-array field dtypes (see zarr-io/03 comments).
  zarr-io/05 must write the `null` raw, and the human should decide on rec-array dtype fidelity in zarr (ADR 0005, zarr-io/07)

- [ ] Delete the stale unpacked `tests/testthat/fixtures/zarr/` (ignored by git and the build, but unused), the shell denied `rm`

- [ ] Writing a large int64 (or complex) array to zarr through the split-parts writer hangs: a 2^19 x 3 int64 matrix never finished in `zarr_write_read()` (zarr-io/05 shrank the test with the `anndata.zarr_chunk_limit` option instead of finding the cause). Find and fix the slow path, then add a test that writes a 2^19 x 3 int64 matrix in seconds.

## Blocked

## Follow-up

Tickets that need triage before they can be queued.

- zarr-io/13: zip stores (`.scratch/zarr-io/issues/13-zarr-zip-stores.md`)
- h5ad-io/15: rec-array field dtype fidelity (`.scratch/h5ad-io/issues/15-rec-array-dtype-fidelity.md`), after the MVP
