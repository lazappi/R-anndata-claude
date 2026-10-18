## Committing

- You are allowed to commit as needed in this project
- You should acknowledge yourself on commits. When working as an autonomous agents, always do this.
- Each commit should be an atomic unit of work
- This project uses gitmoji commits, do not use conventional commits
- Keep commit messages clear and brief

## Agent skills

### Issue tracker

Issues are tracked as local markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` plus `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Specifications

- Start at `.scratch/roadmap/spec.md`, which lists the sub-projects and their order
- Python anndata 0.13.4 is the only reference, fetch it with `scripts/fetch-reference.sh` (to `.reference/anndata/`)

## Ralph loop

- Development runs as a Ralph loop: `scripts/ralph.sh` feeds `PROMPT.md` to a fresh `claude -p` run per item in `fix_plan.md`
- Loop runs use `ralph/settings.json` (Sonnet, no plugins, project subagents only, no edits to specs, ADRs or loop config)
- Project subagents are defined in `.claude/agents/`: `searcher` and `checker` (Haiku), and `python-oracle` and `reviewer` (Sonnet)
- Create a `STOP` file at the root to stop the loop after the current run
- `scripts/ralph.sh --resume "<message>" <runs>` resumes the last run's session with a message (such as decisions), then continues the loop
- Versions use tidyverse-style development numbers (`0.0.1.9000`), bumped by one in the fourth component and tagged `v<version>` only when a ticket is done
- Releases (such as `v0.0.1`, the MVP) are set by the human, and `NEWS.md` collects user-visible changes under the development version heading

## Build, test and learnings

Kept brief and current by the loop.

- `scripts/fetch-reference.sh` fetches the Python reference to `.reference/anndata/`
- `scripts/check.sh` is the full check that must pass before every commit, and `scripts/check.sh --quick <test files>` is for use during development (`--quick` takes test file paths and lints only changed R files)
- The registry binds named functions late (`late_bound()`), otherwise covr reports registered encodings as uncovered
- Coverage is not part of the full check, run `scripts/check.sh --coverage` for the report (target at least 90%)
- `scripts/check.sh` runs tests on 4 workers (`TESTTHAT_CPUS`) and fails with "timed out" after 570s (`ANNDATA_CHECK_TIMEOUT`), killing every child process, so a hanging test or a too-slow suite fails fast instead of outliving the agent's 10-minute command limit
- The full check fails on any NOTE (`error_on = "note"`) and sets `_R_CHECK_SYSTEM_CLOCK_=false` itself
- `LICENSE` needs `ORGANIZATION` as well as `COPYRIGHT HOLDER`, otherwise check gives a note
- Placeholder `@importFrom` lines in `R/anndata.claude-package.R` silence the unused-Imports note, remove each once real code uses that package
- `air.toml` and `.lintr` exist, check with `air format --check .` and `lintr::lint_package()`
- `R CMD check` gives a NOTE "unable to verify current time" unless `_R_CHECK_SYSTEM_CLOCK_=false` is set, so always set it.
  Never treat a NOTE as acceptable.
- The full check's document step fails if `man/` is new or changed, so run it once (it writes the files) then rerun
- Matrix classes: use `Matrix::t()` (base `t()` misses the S4 method in tests) and `as(x, "lMatrix")` (`as(x, "lgCMatrix")` is deprecated)
- `DataFrame` rejects `NA` row names via `rownames<-` and `DataFrame(row.names=)`, so set them with `with_frame_names()` (slot assignment), and the index name is kept in `metadata(df)$index_name`
- Variables only used inside cli `{}` strings trip `object_usage_linter`, so compute values inline or pass them as condition fields
- `AnnData` is `AnnDataClass` (R6, `R/anndata.R`) wrapped by `AnnData()`: roxygen needs `@noRd` on the class, `@importFrom R6 R6Class` stays in the package file and `.lintr` allows the names `AnnData`, `AnnDataClass` and `X`
- The project uses roxygen2 8 (`Config/roxygen2/version` in `DESCRIPTION`) and lintr 3.4.0, so keep the Rd files and `DESCRIPTION` that `devtools::document()` writes
- rhdf5 2.57.12 segfaults in `h5read(native = TRUE)` on any scalar (0-d) dataset, so use `native = FALSE` there (the package never calls `h5read()`)
- S3 methods for `$`, `[[` and similar need a plain `@export` tag (`@exportS3Method` breaks roxygen), and `R CMD check` needs `devtools::document()` to have registered them in `NAMESPACE`
- Inside R6 classes with custom `$` methods use `.subset2()` and `private`, not `self$`, and `adata$obsm[["k"]] <- v` assigns the mapping back to the active binding, so it must ignore an identical value
- `expect_anndata_condition()` unwinds at the condition, so for warnings whose assignment must complete (then check state) use `expect_warning(..., class =)`
- Layers are the aligned mapping class with X under the `NA` key, so look keys up with `match()` and never `[[`
- Active bindings in package-level objects are lost on install, so create them in `.onLoad()`
- Snapshots are only written by `scripts/check.sh --quick`, because `R CMD check` runs in a temp copy
- Lint runs after `pkgload::load_all()` so cross-file internals are visible to `object_usage_linter`
- Fixtures are regenerated with `scripts/regenerate-fixtures.sh` (cases registered in `tests/python/generate_fixtures.py`), and a test checks they match a fresh generation, so recommit them when a case changes
- rhdf5 gotchas are in `.scratch/h5ad-io/rhdf5-spike.md`: read with `native = TRUE`, and use the low-level `H5D`/`H5A` API because high-level writes add `rhdf5-NA.OK` attributes and gzip
- `.scratch/h5ad-io/encoding-table.md` has a generated block: after changing an encoding case, run `uv run --project tests/python python -I tests/python/encoding_table.py tests/testthat/fixtures .scratch/h5ad-io/encoding-table.md`, because a test checks it is current
- Non-h5ad Python expectations are JSON written by a `tests/python/*_cases.py` script into `tests/testthat/fixtures/`, run from `scripts/regenerate-fixtures.sh` and guarded by a freshness test (see `make_unique_cases.py`)
- Python's `logger.info` calls become `rlang::signal(class = "anndata_info_message")` (silent unless handled), test them with `withCallingHandlers()`
- In Python fixture scripts pass plain lists to `pd.DataFrame(..., index=)`, because a `pd.Series` with a default index is reindexed to all `NA`
- `air format` rewrites `×` escapes to literal characters, which gives an R CMD check non-ASCII WARNING, so build such characters with `intToUtf8()`
- `.Generic` in group generics (`Ops`) trips `object_usage_linter`, so read it with `get(".Generic", envir = environment())`
- The element registry (`R/io-registry.R`) is internal until ticket 05: encodings call `register_writer()`/`register_reader()`, tests use `local_io_registry()` and `local_h5_store()` from `helper-io.R`
- On-disk dtype records (`R/dtype.R`) are the `anndata_dtype` attribute plus S3 class `anndata_typed` for plain arrays, so use `set_dtype()`/`drop_dtype()`, compare classes with `drop_dtype()` in tests and allow `typed_class` in `is.object()` checks
- rhdf5 gives no dataset sign from a dataset handle, so `read_dataset(loc, name)` takes a group or file handle and uses `h5ls`, and `H5Dread(bit64conversion = "double")` warns exactly when 64-bit values reach 2^53
- Readers are called `fn(elem, path, store)`, and files calling `register_*()` at top level must collate after `io-registry.R` (e.g. `io-values.R`)
- A scalar Element has no `dim` and a 1-element array has `dim` 1 (`as_array()`), and complex128 types come from a throwaway `h5createDataset(storage.mode = "complex")`
- Nullable Elements keep an `anndata_nullable` record and factors with non-string categories keep `anndata_categories`, `drop_dtype()` removes the first, and a write that passes the record on to a nested `write_elem()` recurses forever
- Test helpers shared between files (`read_fixture_elem()`, `write_fixture_like()`, `read_written()`) live in `helper-io.R`
- Sparse `data`, `indices` and `indptr` are plain datasets with no Encoding attributes, so `R/io-sparse.R` uses `write_dataset()` and `read_values()` and not `write_elem()`/`read_elem()` (which reject unencoded Elements)
- Open files that are only read with `H5Fopen(path, flags = "H5F_ACC_RDONLY")`, because the default takes a write lock and breaks parallel tests that read the same fixture from h5py
- Rec-arrays (`R/io-values-rec-array.R`): `H5Dread(bit64conversion = "double")` keeps `u4`/`i8` values, bool fields read as factors, `h5writeDataset(<data.frame>, store, key, level = 0L, chunk = nrow)` writes the compound, and anndata cannot read non-ASCII fixed-length strings so writing them raises
- `h5ls` lists a dict's members alphabetically, so a dict reads back in that order, and `result[i] <- list(NULL)` is how to keep `NULL` members
- Text in `abort_unwritable(path, what)` is plain, the braces of `what` are not interpolated by cli
- `expect_structurally_equivalent(a, b, rec_array_paths =)` exempts only the dtype and digest of those datasets, and `expect_rec_array_values_equal()` compares field names, order and values through Python
- Dataframes (`R/io-values-dataframe.R`): a non-string index lives in `metadata(df)$index_source`, and a string read from a plain `string-array` carries the nullable record `FALSE` (written back as `string-array`)
- `expect_python_equal()` and `rewrite.py` differ in scope: the first compares whole AnnData files, the second rewrites with Python's default settings
- A `local_anndata_settings()` call inside a test loop leaks to later iterations, so call it from a function run per case
- Python is only used through `uv run --project tests/python ...`, in tests via `run_python()` which sets a private `TMPDIR` (uv lock files left in the check temp dir cause a NOTE), and which finds the uv interpreter once and calls it directly
- Deprecated methods call `warn_deprecated(method, advice, rlang::caller_env())` (`anndata_deprecated_warning` + `anndata_future_warning`), tests wrap them in `quiet_deprecated()`, and the lifecycle badge goes in the `AnnData()` help page because the R6 class is `@noRd`
- `AnnData()` rejects arrays above 2-D but the `X` and layers setters only warn, so build 3-D cases by assigning, and `read_anndata_elem()` sets them after construction
- `expect_warning()` returns the condition not the value, so call the code again inside `suppressWarnings()` to inspect the result
- `scripts/check.sh` lints only changed files, and a new R file that vanished from disk shows in `git status`, so check it is listed
- `expect_python_equal()`, `python_rewrite_h5ad()` and `compare.py` take many files per Python process, use them for whole h5ad files
- Compression (`R/io-compression.R`) rides in `dataset_kwargs` (with an internal `as_dense` key), rhdf5 type handles are digit strings (tell predefined types by the `H5T_` prefix), `H5Pset_lzf()` segfaults on variable-length strings and `H5Pset_chunk()`/`H5Pget_chunk()` use HDF5 (row-major) order
- `as(<dense>, "CsparseMatrix")` gives a symmetric class for symmetric input, so go through `"generalMatrix"` first
- `gen_adata` needs `awkward`, which the uv environment lacks, so `_realistic_adata()` stubs `helpers.gen_awkward` and seeds the global `np.random` too
- Real-world downloads are legacy format, so `python_rewrite_h5ad()` them first, and `expect_all_equivalent(sorted_paths =)` skips the digest of sparse datasets stored unsorted (ADR 0006)
- `.lintr` excludes `.scratch`, so throwaway scripts there are not linted (air still formats them)
- zarr uses `Rarr` devel (`Remotes: Huber-group-EMBL/Rarr@devel`), verdicts in `.scratch/zarr-io/zarr-spike.md`: always pass `data_type` to `write_zarr_array()` (it narrows integers), use `write_zarr_group(path, group = "")` for the root, and use `"|b1"` for bool
- Encodings never call rhdf5: they use the store layer (`R/io-store.R`, wrappers over `store_backend(store)$op()`, HDF5 in `R/io-store-h5.R`), a list of functions and not S3 methods because `.lintr` rejects dotted names, and a zarr backend adds its own list
- `array_read(store, path, selection)` takes strictly increasing indices per dimension in numpy order, and strings and complex are read whole and subset in R because HDF5 crashes reading them through a memory dataspace
- zarr fixtures are the archive `tests/testthat/fixtures/zarr-fixtures.tar.gz` (a directory tree gives `R CMD check` NOTEs for hidden `.zarray` files and long paths), so use `zarr_fixture_path()` in tests and `pack_zarr_fixtures.py` to pack, and `expect_structurally_equivalent()` takes zarr store directories too (`zarr_tree.py`)
- A consolidated zarr store hides edits to child metadata from Python's reader, so edit the unconsolidated variant in tests
- zarr reading (`R/io-store-zarr.R`, `zarr_open()`, handle class `zarr_node`) reads each node's own metadata and never `.zmetadata`, and Rarr gives `NA` for 64-bit and uint32 values beyond the integer range and cannot read complex, so `zarr_split_read()` re-reads those from a temporary copy with a trailing dimension of uint16 or float64 parts (always for int64, uint64 and uint32, because Rarr warns once per out-of-range value, which takes minutes on big arrays)
- `for (x in <named vector>)` drops the names, so loop over `names()` or indices when the name matters
- zarr writing (`R/io-store-zarr-write.R`, v3 only): we write every `zarr.json` and Rarr only the chunks, Rarr takes numpy `data_type` strings (`"<i4"`) and needs a `dim()` (even 1-d), and Rarr skips a chunk equal to the fill value and writes empty attributes as `[]` (so `zarr_consolidate()` is our own)
- Python's `read_elem` returns numeric scalars as plain `int`/`float` (zarr and h5ad), so a Python rewrite widens them to int64/float64 and complex scalars cannot be rewritten: R -> Python -> R tests compare their values only
- zarr existence checks must match case (`zarr_node_exists()`), because macOS finds `x` as `X`, and test fixture filters on `x` must exclude `anndata_*` cases
- zarr rec-arrays (`R/io-store-zarr-table.R`) are v3 `struct` arrays packed in R with zstd via `zarr_zstd()`/`zarr_unzstd()`, signed 64-bit values are decoded as minus the complement plus one (two's complement is not exact in a double), and `rec_array_values.py` only reads HDF5
- Python's `read_zarr` returns `raw = None` for a Raw with no observations, so leave `anndata_raw_0_obs` out of tests where Python reads a zarr store, and `rewrite_h5ad.py`/`compare.py` take zarr directories (a `.zarr` output converts formats)
- zarr compression (`zarr_compressor_arg()`): Rarr's gzip is zlib and Python's gzip codec rejects it, so gzip chunks are written uncompressed by Rarr then gzipped with `zarr_gzip_chunks()`, and Rarr ignores zstd levels (metadata only)
- `write_elem()` always rejects `/` in keys for a zarr group (Python does, whatever `disallow_forward_slash_in_h5ad` is), so check the Python registry before assuming h5ad and zarr behave alike
- zarr rec-array chunks are compressed with `zarr_compress()` and read with `zarr_decompress()` (gzip in R, zstd and blosc through Rarr as a 1-d uint8 array), and `compressors` variants of the fixtures come from `VARIANT_CASES` in `generate_zarr_fixtures.py`
- zarr sharding (`zarr_shard_files()`): arrays are written as inner chunk files then repacked into shard files, and tests of chunk shape or codecs must read inside `sharding_indexed` (`zarr_codec_names()`, `zarr_inner_chunk_shape()` in `test-io-zarr-anndata.R`) or pass `shards = NULL`
- zarr v2 reads through the same store layer, and only rec-arrays differ (a structured `dtype` list, decoded by `zarr_v2_unpack()`), so test odd v2 layouts on an edited copy of a fixture's `.zarray` (`local_v2_rec_array()`)
- zarr rec-array fields carry dtype records (`"uint8"`, `"<type>:<length_bytes>"` for strings), `rec_array_field(zarr = TRUE)` keeps them and bool, Python does not shard rec-arrays by default (only with explicit `shards`), and tests of HDF5-sourced rec-arrays still need `rec_array_paths`
- The View operations table is `tests/testthat/fixtures/view_cases.json` (from `view_cases.py`, rows keyed by operation name, layers' X under `"None"`), and `write_loom(write_obsm_varm = True)` stops Python printing notes that would otherwise leak into script output
- Views (`R/index.R` `subset_view()`): `private$.view` holds the parent and positions, lazy parts reload on access, `ensure_actual()` detaches on any change, and internal calls on a mapping's methods need `.subset2()` because a key like `load` hides them through `$`
- View copy-on-write: setters validate first then call `ensure_actual(what, kind, call)` (which warns), R cannot tell nested from whole assignment so `what` is fixed per setter, and `private$put(key, validate(...))` must force validation before `touch()` (lazy arguments)
- The backed operations table (`tests/testthat/fixtures/backed_cases.json`, from `backed_cases.py`) is keyed `operations[name][kind][mode]`, with `raw_operations` for writes on files with `raw`, and the script copies a template file per case to stay near 20s
- Backed mode (`R/backed.R`): `read_h5ad(backed=)` sets `read_state$backed` (the file manager), X and `raw/X` become placeholder `backed_x` objects, `reopen_backed()` reopens a closed file on X access, and tests use `local_backed()`/`file_is_free()` (HDF5 refuses a read-write open of a file held read-only) from `helper-backed.R`
- A new S3 method like `dim.backed_x` is invisible to `nrow()` inside the package until `devtools::document()` writes it to `NAMESPACE`, and R6 finalizers must be private
- Backed sparse X (`R/backed-sparse.R`) reads `indptr`, then `array_read()` of `data` and `indices` at the needed offsets, and mocked `array_read` paths are absolute (`/X/data`), so test with `endsWith()`. A Matrix subset drops the dtype record, so wrap it in `copy_dtype()`
- Sparse parts are written resizable (`dataset_kwargs$resizable`, unlimited and chunked) so `sparse_dataset()$append()` works, a backed handle's shape lives in its `state` environment (`backed_shape()`), and rhdf5 gives no file intent from a group handle (`append()` probes with a temporary attribute)
- Rarr's `is.compact()` takes any ALTREP integer (such as `sort()` output) for a range, so `zarr_selection_index()` makes selections plain with `+ 0L`, and an h5ad selection read of int64, uint32 or uint64 is `integer` where zarr gives `double` (fix a seed's `type()` from the dtype)
- Writing backed objects (`write_h5ad()` in `R/io-h5ad.R`): the function closes the backing file but only the `write()` method re-points the manager (`set_filename()`), a View looks through `view_info()$parent` because its own manager is empty, and `write_elem(store, "/")` wipes the root so in-place updates use `write_anndata_members()`
- `isbacked` is a filename plus X not held in memory (Python's `Layers.isbacked`), so assigning X keeps `filename` and ends backed mode, `[<-.backed_dense` writes HDF5 blocks from `t(block)` (row-major), and a View of a backed object refuses changes except replacing X (`ensure_actual()`)
- A backed dense X is copied by `write_backed_dense()` (`R/backed-copy.R`, h5 targets only): `H5Pget_chunk()` returns numpy order and `H5Pget_layout()` tells chunked from contiguous, and `h5_write_block()` is the shared hyperslab writer
- The lazy operations table (`tests/testthat/fixtures/lazy_cases.json`, from `lazy_cases.py`) is keyed `section[row][format]` (`h5ad`, `zarr_v3`, `zarr_v2`), and Python's lazy frame column order varies per run so the script sorts it
- `array_info()` has list columns `shape` and `chunks` in numpy order (rhdf5 extent dims are reversed, `H5Pget_chunk()` is not), `chunks` is the inner shape for sharded zarr, and `h5_tree.py`/`zarr_tree.py` report `chunks` too
- Each Python start costs 0.3s (`h5_tree.py`) to 1.8s (anything importing anndata), so never call it per case: write all files first, then use `prefetch_h5_trees()`, `python_rewrite()` and `expect_all_equivalent()` (testthat's per-test times do not show this cost)
