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
- Versions use tidyverse-style development numbers (`0.0.0.9000`), bumped by one and tagged `v<version>` only when a ticket is done

## Build, test and learnings

Kept brief and current by the loop.

- `scripts/fetch-reference.sh` fetches the Python reference to `.reference/anndata/`
- `scripts/check.sh` is the full check that must pass before every commit, and `scripts/check.sh --quick <test files>` is for use during development (`--quick` takes test file paths and lints only changed R files)
- Coverage is not part of the full check, run `scripts/check.sh --coverage` for the report (target at least 90%)
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
- Each Python start costs 0.3s (`h5_tree.py`) to 1.8s (anything importing anndata), so never call it per case: write all files first, then use `prefetch_h5_trees()`, `python_rewrite()` and `expect_all_equivalent()` (testthat's per-test times do not show this cost)
