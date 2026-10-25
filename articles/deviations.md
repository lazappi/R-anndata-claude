# Differences from Python anndata

anndata.claude follows Python anndata 0.13.4. Observable behaviour
(values, errors, warnings, printed output and files written) matches
Python except where this page says otherwise. Each deviation has a
reason and the ticket or decision record it comes from. Tickets are in
`.scratch/<sub-project>/issues/` and decision records (ADRs) in
`docs/adr/` of the source repository. Help pages with deviations have a
“Deviations from Python” section that links here.

Deviations on disk are rare, because files must round trip with Python.
The ones that exist are under “On-disk files”.

## Indexing and assignment

- **R indices.** Indices are 1-based, negative integers exclude, logical
  vectors need the full axis length and character vectors match names
  (first match). Zero, `NA`, unknown names and mixed signs raise
  `anndata_index_error`. Reason: R semantics (roadmap principles,
  core-object spec “Subsetting”). Help page: `?anndata-index`.
- **Mapping keys.** Keys of `obsm`, `varm`, `obsp`, `varp`, `layers` and
  `uns` must be single non-empty strings, because R lists cannot hold
  `NA` or empty names. Python accepts any key (core-object/05).
- **Data frames in `obsp` and `varp`.** A data frame is an error. Python
  converts a homogeneous one to an array, but the spec allows only
  matrices (core-object/05).
- **Non-character `obs_names` in a list.** A list of obs with
  non-character names is coerced to character with an
  `anndata_implicit_modification_warning`. Python keeps them
  (core-object/02).
- **Assigning `obs` and `var`.** A value without its own names resets
  the names to `"0"`, `"1"`, … as in Python, and `obs_names<-` accepts
  duplicates without a warning (Python warns only at construction), see
  core-object/07.
- **`raw$X` and `raw$var` can be assigned.** R keeps validated setters
  so that `adata$raw$var$col <- v` works, where Python modifies them in
  place (core-object/08).

## Views

Help page:
[`?AnnData`](https://lazappi.github.io/R-anndata-claude/reference/AnnData.md)

- **Accessors return plain R values.** In Python
  `x = view.X; x[0, 0] = 1` modifies the View, but in R
  `x <- view$X; x[1, 1] <- 1` only changes `x`. Assign through the View
  (`view$X[1, 1] <- 1`) instead. Reason: R values are copied on
  modification (ADR 0002 and views spec).
- **Warnings are broader.** R cannot tell `view$obs$col <- x` from
  `view$obs <- x`, so setting `obs`, `var`, `uns` or `X` always makes
  the View actual with a warning, where Python is silent for some forms
  (views/03). An item assignment on `X`, `layers` or `obsm` says
  “Setting element” where Python says “Trying to modify attribute”.
- **Nested values are snapshots.** A change to a nested value of `uns`
  never reaches the parent, and `view$obs$num[1] <- v` detaches instead
  of raising pandas’ `ChainedAssignmentError` (views/02 and views/03).
- **View of a backed object.** `view$X[1, 1] <- 5` makes the View actual
  with a warning, where Python silently changes nothing (backed/05).

## Backed mode

- **`copy()` to the same file twice.** Python overwrites the first
  copy’s open file in `"r+"` mode but rhdf5 cannot truncate an open
  file, so R raises an error in both modes (backed/05).
- **Writing a View of a backed object in place.** Python writes a
  corrupt file and fails, R refuses with
  `anndata_invalid_argument_error` (backed/05). Moving a backed View’s
  file fails before anything is moved (`anndata_file_not_found_error`
  when the move fails), where Python renames the file first and leaves
  it corrupt.
- **Writing to an existing file.** Writing to a new path that exists
  truncates it, where Python opens it in append mode and updates it
  (backed/05).
- **Backed `raw`** (backed/05). Writing a backed `raw` in place raises
  `anndata_not_supported_error` (Python fails with `AttributeError`),
  and writing it to a new file works. `filename <- NULL` keeps the
  values of `raw$X`, where Python leaves `None`. `raw$X<-` exists in R
  for nested assignment but is refused on a backed `raw`.
- **`chunked_X()` is not a generator.** It returns a list of
  `list(chunk, start, end)` with 1-based inclusive rows, not a generator
  with 0-based half-open ranges (backed/06).

## Lazy reading

Help pages:
[`?read_lazy`](https://lazappi.github.io/R-anndata-claude/reference/read_lazy.md),
[`?read_elem_lazy`](https://lazappi.github.io/R-anndata-claude/reference/read_elem_lazy.md)
and `?lazy-dense`

- **`uns` is read eagerly.** Python keeps arrays inside `uns` as dask
  arrays (lazy/07).
- **[`t()`](https://rdrr.io/r/base/t.html) of a lazy `AnnData` stays
  lazy.** It fails with a `ValueError` in Python, which is a bug there
  (lazy/07).
- **Lazy frames are indexed by row name.** Python’s `Dataset2D` has no
  `loc` (lazy/07).
- **[`read_elem_lazy()`](https://lazappi.github.io/R-anndata-claude/reference/read_elem_lazy.md)
  takes a path or handle.** R has no element object like h5py’s
  (lazy/07).
- **An int32 array holding -2^31.** `NA_integer_` has the same bit
  pattern, so a lazy seed (whose type is fixed before reading) raises
  `anndata_dtype_overflow_error` when such a block is realised, and
  suggests an eager read (lazy/04).
- **R types.** Lazy arrays have DelayedArray’s R types and not the
  promoted On-disk dtype (concat/06).

## Concatenation

Help page:
[`?concat`](https://lazappi.github.io/R-anndata-claude/reference/concat.md)

- **Lazy `obs` and `var` are read into memory.** Python keeps them lazy,
  which loses categorical columns and fails on an outer join with string
  columns (concat/06).
- **Mixed `object` columns.** Annotation columns that Python would turn
  into a mixed `object` column (numbers with strings, bool with numbers)
  raise `anndata_unsupported_value_error`. Keys are converted to
  character (concat/03).

## Reading other formats

Help page:
[`?read_excel`](https://lazappi.github.io/R-anndata-claude/reference/read_excel.md)

- **[`read_excel()`](https://lazappi.github.io/R-anndata-claude/reference/read_excel.md).**
  Python’s `object` X (text in the first column) has no R form, so X is
  numeric. Names are always strings, even with `restrict_index_types`
  off (other-formats/07).
- **[`read_umi_tools()`](https://lazappi.github.io/R-anndata-claude/reference/read_umi_tools.md).**
  A row with a missing field raises `anndata_invalid_value_error`, where
  Python reads a missing last field as a `NaN` count (other-formats/05).
- **Complex Matrix Market files.**
  [`read_mtx()`](https://lazappi.github.io/R-anndata-claude/reference/read_mtx.md)
  rejects the `complex` field, where Python silently drops the imaginary
  part (`wontfix`, `fix_plan.md`).
- **Unsupported formats.** Loom is not supported (deprecated in Python,
  roadmap spec), nor are zip stores and writing zarr v2 (`NEWS.md`).

## Reading and writing h5ad

- **Invalid arguments are classed errors.** Errors are raised before the
  file is opened. `chunk_size` of 0 or less is an error (Python hangs)
  and `as_sparse` on a sparse X is `anndata_invalid_argument_error`
  (Python gives an `AttributeError`). The `/raw` group keeps its
  Encoding attributes when raw X is written dense (Python drops them)
  (h5ad-io/11).
- **Old releases.** Files from anndata before 0.6 and 0.6.x zarr stores
  are not supported (legacy-formats spec).

## On-disk files

- **`NA` and `NaN`.** Double `NA_real_` and `NaN` are both written as
  `NaN`, and read back as `NaN` (h5ad-io spec, “Encodings”).
- **Out-of-range sparse indices.** Help page:
  [`?h5ad`](https://lazappi.github.io/R-anndata-claude/reference/h5ad.md).
  A CSR or CSC matrix whose `indices` are out of range for its shape
  (such as the 1-based indices Illumina DRAGEN 4.5.4 writes) raises
  `anndata_io_registry_error`, with a hint when they look 1-based.
  Python reads such a file without complaint into an invalid scipy
  matrix (`check_format()` fails and `toarray()` misplaces values), and
  `Matrix` cannot hold an invalid matrix.
- **Unsorted sparse indices.** Unsorted `indices` of a CSR or CSC matrix
  are sorted on read, with their `data`, because `Matrix` needs them
  sorted. The matrix is the same but the on-disk order of `indices` and
  `data` can differ (ADR 0006).
- **Compression of rec-arrays.** Help page: `?io-rec-array`.
  `compression = "lzf"` writes an HDF5 rec-array uncompressed, because
  the compound helper only supports gzip (ADR 0008 and h5ad-io/15).
- **zarr rec-array chunks.** A zarr rec-array is written as one chunk,
  where Python uses zarr’s `guess_chunks` (zarr-io/14).
- **complex64.** Reading complex64 raises a classed error naming the
  path, because rhdf5 cannot read it (h5ad-io spec, “Encodings”).

See also
[`vignette("anndata-claude")`](https://lazappi.github.io/R-anndata-claude/articles/anndata-claude.md)
for an overview.
