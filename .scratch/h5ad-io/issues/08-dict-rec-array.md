# Dict and rec-array

Status: ready-for-agent
Type: task
Blocked by: 05, 06

## What

Register `dict` 0.1.0 and `rec-array` 0.2.0.

- Named lists, including nested and empty dicts, and `null` values
- Unnamed or partly named lists raise `anndata_io_registry_error`
- `rec-array` read into a marker-class `data.frame` keeping field names, order and dtypes, including fixed-length byte and unicode fields, and written back with the same compound type
- Fixtures including a scanpy `rank_genes_groups`-shaped uns

## Acceptance criteria

- All three round-trip directions pass for each fixture
- `scripts/check.sh` passes

## Decisions (human, 2026-10-15)

- rec-array follows the updated spec section and ADR 0005: names, order and values round trip, field dtypes do not.
  Write with rhdf5's compound writer, sizing fixed-length string fields to the longest value in bytes.
- Round-trip tests compare field values in every direction (Python → R → Python with Python's own comparison of the field values), with an explicit, narrowly scoped relaxation of Structural equivalence for rec-array field types
- Document the deviation in the help pages

## Decisions (human, 2026-10-16)

- Keep the error on write for string fields with non-ASCII text, because Python cannot read them back (ADR 0005 promises that Python reads every R-written `rec-array`).
  h5ad-io/15 lifts it.
- For `rec_array_basic` and `rec_array_object_field`, the R write direction tests that writing raises `anndata_io_registry_error`, and the Python to R direction is tested as before
- `dataset_kwargs` for rec-arrays and rec-arrays with no rows move to h5ad-io/15

## Comments

2026-10-16 (loop run)

Done: `dict` 0.1.0 (`R/io-values-mapping.R`) and `rec-array` 0.2.0 (`R/io-values-rec-array.R`, marker class `anndata_rec_array`, made by `new_rec_array()`).
All three round-trip directions pass for the dict fixtures and for the ASCII rec-array fixtures (`rec_array_widths`, `rec_array_rank_genes_groups`) plus an ASCII variant of `rec_array_basic` built in R.
Added the fixture `rec_array_int64_big` (reading raises `anndata_dtype_overflow_error`), the helper `expect_rec_array_values_equal()` and the `rec_array_paths` argument of `expect_structurally_equivalent()`, which exempts only the `dtype` and `digest` of the named datasets.
Reading uses `bit64conversion = "double"`, so `u4` and `i8` fields keep their values.
The file names start `io-values-` so that they collate after `io-registry.R`.

**Blocked on a human decision.** The decision above says fixed-length string fields are sized in bytes "so non-ASCII text survives".
That holds for h5py but not for anndata: `_from_fixed_length_strings` (`anndata/compat/__init__.py:297`) turns every `S` field into `U`, which decodes as ASCII.
`anndata.io.read_elem` (so `read_h5ad`) fails with `UnicodeDecodeError` on an R-written rec-array with any non-ASCII text, and the same happens for UTF-8 fixed strings, since h5py maps both to `S`.
So acceptance criterion 1 cannot be met for `rec_array_basic` and `rec_array_object_field`, which hold `yé` and `bé`, and no fixed-length string field can fix that.
What I did: a string field with non-ASCII text raises `anndata_io_registry_error` on write (documented in the help), rather than write a file Python cannot read.
Reading non-ASCII rec-arrays from Python works.
Question: keep the error until h5ad-io/15 (variable-length UTF-8 fields, which fix this), or write the file anyway as the decision says?
Recommended: keep the error, and let ticket 15 lift it.
Also not done: `dataset_kwargs` (compression) is ignored for rec-arrays, which are written uncompressed, and a rec-array with no rows raises on write (rhdf5 needs a non-empty chunk).
