# Fix plan

The prioritised queue for the Ralph loop (see `PROMPT.md`).
Each run takes the first unblocked item.
The loop may tick items, split them into sub-items and add Discovered and Blocked entries.
The human owns the order of the Queue.

## Queue

- [x] foundations/10: faster test suite, again (`.scratch/foundations/issues/10-test-speed-again.md`), target relaxed to 7 minutes (see Decisions)
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
- [x] zarr-io/06: zarr v3 dense, string, scalar, null and sparse Elements (`.scratch/zarr-io/issues/06-zarr-v3-basic-elements.md`)
- [x] zarr-io/07: zarr v3 nullable, categorical, dataframe, dict and rec-array Elements (`.scratch/zarr-io/issues/07-zarr-v3-compound-elements.md`)
  - [x] nullable arrays, categorical, dataframe and dict
  - [x] rec-array: zarr `table_read`/`table_write` for the v3 `struct` data type (own chunk packing, zstd via Rarr), three round-trip directions on the `rec_array_*` fixtures
- [x] zarr-io/08: read_zarr, write_zarr and settings (`.scratch/zarr-io/issues/08-read-write-zarr.md`)
  - [x] `read_zarr()`, `write_zarr()`, `adata$write_zarr()`, `chunks`, settings, whole-AnnData round trips and cross-format checks
  - [x] dataset arguments: compression (`compressor`/`compressors` with zstd, gzip, blosc) and `shards` (the sharding itself is ticket 09), dropped for scalars and nulls
  - [x] Python's warning for `zarr_write_format = 2` (moved to ticket 11, as v2 is refused until then) and the zarr `unwriteable` details (already tested in `test-io-h5ad.R`)
  - [x] vignette-independent NEWS entry for zarr (the settings help text changes with ticket 09, sharding)
  - [x] `read_elem()`/`write_elem()` tests on zarr groups with a path and error parity with h5ad (forward slashes, bad keys)
- [x] zarr-io/09: writing sharded zarr v3 (`.scratch/zarr-io/issues/09-zarr-shard-writing.md`)
- [x] zarr-io/10: reading zarr v2 (`.scratch/zarr-io/issues/10-zarr-v2-read.md`)
- [x] zarr-io/12: zarr documentation (`.scratch/zarr-io/issues/12-zarr-docs.md`)
- [x] zarr-io/14: zarr rec-array field dtypes and sharding (`.scratch/zarr-io/issues/14-zarr-rec-array-fidelity.md`)
- [x] views/01: view operations table (`.scratch/views/issues/01-view-operations-table.md`)
- [x] views/02: Views: creation, access and Views of Views (`.scratch/views/issues/02-view-core.md`)
- [x] views/03: Views: copy-on-write (`.scratch/views/issues/03-view-copy-on-write.md`)
- [x] views/04: Views: methods and writing (`.scratch/views/issues/04-view-methods-and-io.md`)
  - [x] `transpose()`/`t()` of a View raise Python's error, writing a View to h5ad and zarr reads back as the table says
  - [x] Structural equivalence of a written View with Python writing the same View (`expect_python_equal()`)
  - [x] Table rows with no R method yet: `to_memory`, `write_csvs`, `write_loom`, `chunked_X`, `chunk_X` listed as deferred in `test-views.R` (human decision, see ticket), `write` is under Discovered
- [x] views/05: Views documentation (`.scratch/views/issues/05-view-docs.md`)
- [x] zarr-io/15: zarr rec-array compressors (`.scratch/zarr-io/issues/15-zarr-rec-array-compressors.md`)
- [x] backed/01: backed operations table (`.scratch/backed/issues/01-backed-operations-table.md`)
- [x] backed/02: backed reading and the file manager (`.scratch/backed/issues/02-backed-file-manager.md`)
- [x] backed/03: backed dense X (`.scratch/backed/issues/03-backed-dense.md`)
- [x] backed/04: backed sparse X and sparse_dataset() (`.scratch/backed/issues/04-backed-sparse.md`)
  - [x] `backed_sparse` class, every index form, `sparse_dataset()` reads, Views, dtype records
  - [x] `sparse_dataset()$append()` (table rows `append_*` in `sparse_dataset`, in `"r+"` mode, resizing `data`, `indices`, `indptr` and the `shape` attribute, and invalidating the `indptr` cache in `x$cache`)
  - [x] (moved to `legacy-formats`) h5sparse legacy attributes in `sparse_dataset()` (row `legacy_attributes`)
- [x] backed/05: writing backed objects (`.scratch/backed/issues/05-backed-writing.md`)
  - [x] `write()`/`write_h5ad()` of backed objects, `copy(filename)`, `to_memory()` and Views of backed objects
  - [x] Assigning X in `"r+"` mode (rows `X_assign_*`, `X_item`, `X_del`, `layers_none_assign`, `write_after_X_assign`, `view_*_assign`)
  - [x] The `filename` setter (rows `filename_*`)
  - [x] Chunked copy with `min_rows_for_chunked_h5_copy`
  - [x] Raw rows (`raw_X_assign`, `raw_assign`, `raw_operations`) and `write_obs_edit`
- [x] backed/06: chunked_X, chunk_X and read_elem_partial (`.scratch/backed/issues/06-backed-chunks-and-partial.md`)
- [x] backed/07: backed mode documentation (`.scratch/backed/issues/07-backed-docs.md`)
- [x] lazy/01: lazy seeds spike (`.scratch/lazy/issues/01-lazy-seeds-spike.md`)
  - [x] HDF5Array seeds, ZarrArray and `DataFrame` with DelayedArray columns probed, first draft of `.scratch/lazy/seeds-spike.md`
  - [x] Cause of the own-seed zarr block-read error, and verdicts for the own seed on zarr v3 and v2
  - [x] Own-seed probes for every dtype, bool, nullable and string columns, the 2^53 error, sparse and chunk shape
  - [x] Remaining sparse probes for `H5SparseMatrixSeed` (2^53, result types) and ZarrArray (sparse bool)
- [x] 🛑 Checkpoint (orchestrator): read `.scratch/lazy/seeds-spike.md`, choose the seeds, finish the lazy spec and write its tickets (ask the human only if there is no clear choice)
- [x] lazy/02: lazy operations table (`.scratch/lazy/issues/02-lazy-operations-table.md`)
- [x] lazy/03: seed foundations (`.scratch/lazy/issues/03-lazy-seed-foundations.md`)
- [x] lazy/04: dense lazy seeds (`.scratch/lazy/issues/04-lazy-dense-seeds.md`)
- [x] lazy/05: sparse lazy seeds (`.scratch/lazy/issues/05-lazy-sparse-seeds.md`)
- [x] lazy/06: lazy obs and var (`.scratch/lazy/issues/06-lazy-dataframes.md`)
- [x] lazy/07: read_elem_lazy and read_lazy (`.scratch/lazy/issues/07-read-lazy.md`)
  - [x] `read_elem_lazy()` for every encoding, `chunks`, path and handle stores
  - [x] `read_lazy()` (lazy AnnData with lazy X, layers, obsm, raw, obs and var, `load_annotation_index`)
  - [x] `read_lazy` table rows: compare each row (`default`, `load_annotation_index_*`, `open_handle`, `missing_store`, `unconsolidated_zarr` warning), zarr v2 fixtures, dtypes, and record the eager `uns` arrays as a deviation
  - [x] Operations on lazily read objects: subsetting, Views, `to_memory()`, printing, copy, transpose, writing (the `operations` and `dask_chunks` rows)
- [x] lazy/08: lazy reading documentation (`.scratch/lazy/issues/08-lazy-docs.md`)
- [x] concat/01: concat table (`.scratch/concat/issues/01-concat-table.md`)
- [x] concat/02: concat: axes, joins and arrays (`.scratch/concat/issues/02-concat-arrays.md`)
- [x] concat/03: concat: obs, var and merge strategies (`.scratch/concat/issues/03-concat-annotations.md`)
- [x] concat/04: concat: aligned mappings, pairwise and raw (`.scratch/concat/issues/04-concat-mappings.md`)
- [x] concat/05: concat: Views and backed inputs (`.scratch/concat/issues/05-concat-views-backed.md`)
- [x] concat/06: concat: lazy inputs (`.scratch/concat/issues/06-concat-lazy.md`)
- [x] concat/07: concatenation documentation (`.scratch/concat/issues/07-concat-docs.md`)
- [x] legacy-formats/01: legacy releases spike (`.scratch/legacy-formats/issues/01-legacy-releases-spike.md`)
- [x] 🛑 Checkpoint (orchestrator): read `.scratch/legacy-formats/releases-spike.md`, finish the legacy-formats spec and write its tickets (ask the human only if there is no clear choice) (5 tickets 02-06, all `needs-triage`, awaiting human triage)
- [x] legacy-formats/02: fixture generator and expectation table (`.scratch/legacy-formats/issues/02-legacy-fixtures.md`)
- [ ] legacy-formats/03: unencoded Elements and h5sparse groups (`.scratch/legacy-formats/issues/03-unencoded-elements.md`)
- [ ] legacy-formats/04: legacy dataframes and categories in uns (`.scratch/legacy-formats/issues/04-legacy-dataframes.md`)
- [ ] legacy-formats/05: raw.X, raw.var and the neighbors move (`.scratch/legacy-formats/issues/05-legacy-raw-neighbors.md`)
- [ ] legacy-formats/06: backed, lazy and real-world files (`.scratch/legacy-formats/issues/06-legacy-backed-lazy-real-world.md`)

## Discovered

- [x] `.Rbuildignore` excludes `^tests/python$`, but ticket 06 needs `tests/python` available inside `R CMD check` (tests are copied into the check directory). Fix as part of foundations/06.

- [x] Deadlock: core-object/06 has `Blocked by: 04`, but 04's last sub-item (`layers[[NA]]` assignment) needs 06. The human should remove 04 from 06's `Blocked by:` (06 can then finish 04's sub-item).

- [x] Python 0.13.4 marks `obs_vector`, `var_vector` and the `*_keys()` methods deprecated (they warn). core-object/13 does not warn, because the spec is silent. The human should decide whether to add an `anndata_deprecated_warning`.

- [x] rec-arrays ignore `dataset_kwargs` (compression, ticket h5ad-io/11) and a rec-array with no rows cannot be written, because rhdf5's compound writer needs a non-empty chunk (h5ad-io/15 would fix both)

- [x] `format.AnnData` does not escape control characters in keys as Python's `repr` does (`\n`, `\t`), see `quote_key()` in `R/printing.R`

- [ ] The cellxgene PBMC 3k file (the real-world test download) is in a legacy format that `read_h5ad()` rejects (`anndata_legacy_format_error`, unencoded root Element), so the test reads a Python rewrite of it, reading the original needs the `legacy-formats` sub-project

- [x] Coverage was understated because the registry held uninstrumented function copies under covr, fixed with `late_bound()`, now 96.42%

- [x] Python writes a missing `raw` as a `null` Element in zarr (not in h5ad), and zarr keeps rec-array field dtypes (see zarr-io/03 comments).
  zarr-io/05 must write the `null` raw, and the human should decide on rec-array dtype fidelity in zarr (ADR 0005, zarr-io/07)

- [x] Delete the stale unpacked `tests/testthat/fixtures/zarr/` (ignored by git and the build, but unused), the shell denied `rm`

- [x] Writing a large int64 (or complex) array to zarr through the split-parts writer hangs: a 2^19 x 3 int64 matrix never finished in `zarr_write_read()` (zarr-io/05 shrank the test with the `anndata.zarr_chunk_limit` option instead of finding the cause). Find and fix the slow path, then add a test that writes a 2^19 x 3 int64 matrix in seconds.
  Cause was the read, not the write: Rarr warns once per out-of-range value and the muffling handler made it take minutes. `zarr_numeric_read()` now reads int64, uint64 and uint32 from 16-bit parts always.

- [x] zarr-io/11 must emit Python's `DeprecationWarning` when `zarr_write_format = 2` is used for writing (`zarr.py:244-256`)

- [x] (moved to zarr-io/14) zarr rec-arrays are written unsharded, and `shards = "auto"` is rejected (Python accepts it). Python shards rec-arrays by default, so a human may want parity

- [x] (moved to zarr-io/15) zarr rec-arrays ignore `compressors` (Python honours it) because the struct reader only decodes zstd, and the writer always uses one chunk (zarr-io/14)

- [x] `adata$write()` is missing: Python's `write` is a shortcut for `write_h5ad` (`anndata.py:1744`). Add it as an alias and pass its row of the Views operations table.

- [x] Deadlock for the human: backed/04's last sub-item (h5sparse legacy attributes) belongs to the stub `legacy-formats` sub-project, so backed/04 cannot become `done` and blocks backed/05, 06 and 07 (all `Blocked by: 04`).
  Either move that sub-item out of backed/04 (for example into a legacy-formats ticket) and let 04 finish, or remove 04 from the `Blocked by:` lines of 05 and 06.
  The run on 2026-10-17 skipped to lazy/01 for this reason.

- [x] `resolve_lazy_chunks()` (`R/lazy-dense.R`) forces chunks of at least 1, so a dense array with a zero-length axis has `chunkdim()` larger than `dim()`, which DelayedArray rejects. Use 0 as `StoreSparseSeed` does (Python's layout is `(0,)`) and add a test with an empty dense array.

- [x] Fixed: `h5_attr_write()` writes logicals with `bool_type()`, the full suite passes. Regression from upgrading rhdf5 to 2.57.20 (with R 4.6.1): the categorical `ordered` attribute is now written (or read back) as `uint8` instead of h5py's bool enum, so `test-io-dataframe.R:138` fails Structural equivalence (`/x/c: attribute ordered type differs ("uint8" vs "bool")`).
  The writer builds the enum in `R/io-values.R:78-82`, so check what rhdf5 2.57.20 does with enum attributes (`attr_write()` in the store layer), fix it so Python sees a bool, and look for other bool attributes and datasets hit the same way.
  `scripts/check.sh --tests` stopped at the failure limit, so other regressions may hide behind it: rerun the whole suite with `testthat::set_max_fails(Inf)` once this is fixed.

## Blocked

## Follow-up

Tickets that need triage before they can be queued.

- zarr-io/13: zip stores (`.scratch/zarr-io/issues/13-zarr-zip-stores.md`)
- h5ad-io/15: rec-array field dtype fidelity (`.scratch/h5ad-io/issues/15-rec-array-dtype-fidelity.md`), after the MVP
