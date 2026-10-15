# Core object

Status: ready-for-agent

Sub-project 2 of the roadmap (`.scratch/roadmap/spec.md`) and the first half of the MVP.
It provides the in-memory `AnnData` class, matching Python anndata 0.13.4 behaviour apart from the deviations listed here.

Python references are relative to `.reference/anndata/`.
The main source is `src/anndata/_core/anndata.py`, written below as `anndata.py`.

## Scope

In:

- The `AnnData` R6 class with every Slot (X, obs, var, obsm, varm, obsp, varp, layers, uns, raw)
- Construction, validation and coercion of Slot values
- obs_names and var_names
- Subsetting, which returns copies in the MVP
- The `Raw` class
- Utility methods: `copy()`, `transpose()`, `to_df()`, `obs_vector()`, `var_vector()`, the `*_keys()` methods, `obs_names_make_unique()`, `var_names_make_unique()`, `strings_to_categoricals()` and `rename_categories()`
- Printing
- R generics: `dim()`, `dimnames()`, `nrow()`, `ncol()`, `length()`, `t()`, `[`, `print()` and `format()`

Out:

- Views (`views`).
  `is_view` exists and is always `FALSE`.
- Backed mode (`backed`).
  `isbacked` is always `FALSE` and `filename` is always `NULL`.
  The `filename` and `filemode` constructor arguments error with a "not yet supported" condition.
- `write_h5ad()`, `unwriteable()` and reading (`h5ad-io`)
- `write_zarr()`, `write_csvs()`, `write_loom()`, `chunked_X()`, `chunk_X()` and `to_memory()` (later sub-projects)
- `acc` accessors, `__contains__` with accessors and `__getitem__` with accessor references (`experimental`)
- Array-API, dask and cupy inputs (roadmap non-goals)

## Representation

- `AnnData` is an R6 class (ADR 0002).
  `b <- a` aliases and `a$copy()` copies.
- The orientation is observations × variables in memory, exactly as in Python
- `X` and layer values may be:
  - a base `matrix` (double, integer or logical)
  - a `Matrix` sparse matrix: `dgCMatrix`/`lgCMatrix` (CSC) or `dgRMatrix`/`lgRMatrix` (CSR)
  - `NULL` (X only)
- Sparse format is preserved: CSR stays CSR and CSC stays CSC on every operation in this spec
- Other `Matrix` classes (e.g. `dgTMatrix`, `dgeMatrix`) are coerced on assignment, sparse to CSC and dense to base `matrix`
- `obs` and `var` are `S4Vectors::DataFrame` (ADR 0003).
  Base `data.frame` and named lists are accepted on input and converted.
- Categorical columns are `factor`, with ordered categoricals as `ordered`
- Missing values are R `NA` in every column type
- obsm and varm values may be a matrix, a sparse matrix, an array with 2 or more dimensions, or a `DataFrame`/`data.frame`
- obsp and varp values may be a matrix or a sparse matrix
- `uns` is a named list, nested to any depth
- Values read from disk may carry metadata recording their On-disk dtype (defined in `h5ad-io`), and every operation in this spec must keep that metadata where the values are kept

`X` is stored in `layers` under the `NA` key, mirroring Python's `layers[None]` (ADR 0004).
- `adata$X` is an alias for `adata$layers[[NA]]`, for both getting and setting
- `adata$layers[[NA]]` and `adata$layers[[NA_character_]]` both address X
- `names(adata$layers)` includes `NA` when X is present, in the position Python's key order gives `None` (confirm with fixtures)
- `as.list(adata$layers)` includes X under the `NA` name
- X has the same validation whichever way it is set

## Construction

`AnnData(X = NULL, obs = NULL, var = NULL, uns = NULL, obsm = NULL, varm = NULL, layers = NULL, raw = NULL, shape = NULL, obsp = NULL, varp = NULL)` is exported as a function that wraps `AnnData$new()`.
Arguments after `uns` should be named, as Python makes them keyword-only.
Reference: `anndata.py:244-517`.

- If `X` is an `AnnData`, its Slots are used and any other argument raises an error (`anndata.py:396-411`)
- If `X` is a `data.frame` or `DataFrame`, its row names and column names become obs_names and var_names when `obs` and `var` are not given.
  When they are given, the names must match or an error is raised.
  The frame must be homogeneous (`ensure_df_homogeneous`, `src/anndata/utils.py`) (`anndata.py:420-436`).
- Giving both `shape` and `X` is an error.
  Without `X`, the shape comes from `shape` or is inferred from the other Slots (`anndata.py:1965-2000`).
- obs and var given as a named list use the `obs_names`/`row_names` (or `var_names`/`col_names`) element as the index, if present (`src/anndata/_core/aligned_df.py:36-71`)
- Default names are `"0"`, `"1"`, ..., `"n-1"`, matching Python exactly (`aligned_df.py:47-48`).
  This is a deliberate match so files are identical whichever language created the object.
- A length mismatch between obs/var and the shape raises a dimension error (`_mk_df_error`)
- Non-character names are coerced to character with an `anndata_implicit_modification_warning` ("Transforming to str index"), following `restrict_index_types` (`aligned_df.py:74-100`)
- After construction, duplicate obs_names or var_names (ignoring `NA`) raise `anndata_names_not_unique_warning` when `check_uniqueness` is on (`anndata.py:1590-1600`, `src/anndata/utils.py:298-305`)
- `raw` may be an `AnnData` or a named list with `X`, `var` and `varm`

## Slots and assignment

Each Slot is an active binding on the R6 object.
Assignment validates and coerces as in Python, and invalid values raise classed errors.

- `adata$X <- value`: must have shape `n_obs × n_vars` (`anndata.py:617-661`).
  - A vector or 1-column/1-row matrix is accepted when one dimension is 1, as in Python
  - A scalar fills the matrix and raises `anndata_future_warning`
  - A 2-D value of the wrong shape but the right size is reshaped with `anndata_future_warning`
  - Other shapes error
  - More than 2 dimensions warns (allowed in memory but not writable)
  - `adata$X <- NULL` removes X
- `adata$obs <- df` and `adata$var <- df`: converted as in construction, with the row count checked.
  The current names are kept unless the value brings its own (`anndata.py:752-830`).
- `adata$obs_names <- x` and `adata$var_names <- x`: the length must match, values are coerced to character, and the uniqueness warning applies (`anndata.py:769-819`)
- Aligned mappings (`obsm`, `varm`, `obsp`, `varp`, `layers`) are R6 objects that support:
  - `adata$obsm[["key"]]`, `adata$obsm[["key"]] <- value`, `adata$obsm[["key"]] <- NULL`
  - `adata$obsm$key`, `names()`, `length()`, `as.list()`
  - assigning a whole named list (`adata$obsm <- list(...)`)
- Validation follows `src/anndata/_core/aligned_mapping.py`:
  - axis arrays (`:288-310`): the first dimension equals n_obs (or n_vars), and a data frame value must have row names equal to the obs_names (or var_names), with the matching error otherwise
  - pairwise arrays (`:440-465`): both dimensions equal n_obs (or n_vars)
  - layers (`:371-386`): the first two dimensions equal the shape, and more than 2 dimensions warns
- Clearing or replacing all `layers` (`adata$layers <- list()`, `adata$layers$clear()`) keeps `X` and raises the warning Python raises.
  `adata$layers$clear(keep_x = TRUE/FALSE)` controls this explicitly, as Python's `clear(keep_x=)` does (`aligned_mapping.py:349-370`, release note 0.13.2).
- `adata$uns <- list(...)` must be a named list (or empty), and `adata$uns[["k"]] <- v` sets one entry
- `adata$raw <- other` requires an `AnnData` and stores its X, var and varm (`anndata.py:723-735`).
  `adata$raw <- NULL` removes it.
- Read-only fields: `n_obs`, `n_vars`, `shape`, `is_view`, `isbacked`, `filename`

## obs_names and var_names

- They may contain duplicates and `NA` (ADR 0003)
- The index name (pandas `index.name`) is preserved through every operation and round trip
- `obs_names_make_unique(join = "-")` and `var_names_make_unique(join = "-")` modify in place, following `make_index_unique` exactly (`src/anndata/utils.py:226-292`).
  This includes the counter algorithm, skipping `NA` and the collision warning.

## Subsetting

`adata[i, j]` returns a new `AnnData`.
In the MVP this is an independent copy.
When `views` lands it will return a View with copy-on-write, so nothing outside this sub-project may depend on subsets being copies.

- `i` subsets observations and `j` subsets variables, and either may be missing (`adata[i, ]`, `adata[, j]`).
  `adata[i]` subsets observations only.
- Indices use R semantics (a deliberate deviation from Python):
  - positive integers are 1-based positions and may repeat or reorder
  - negative integers exclude positions
  - logical vectors must have the full axis length (no recycling)
  - character vectors match obs_names/var_names, taking the first match when names are duplicated, and an unknown name errors
  - mixing positive and negative integers errors, and so do out-of-range positions and `NA` indices
- Dimensions are never dropped, so the result is always an `AnnData`, even with one observation or variable
- Result contents follow Python `_init_as_view` and `_mutated_copy` semantics (`anndata.py:292-353`, `:1377-1396`):
  - X and layers are subset on both axes
  - obs, obsm and obsp are subset on observations (obsp on both of its dimensions)
  - var, varm and varp are subset on variables
  - uns is copied unchanged
  - raw is subset on observations only, keeping all of its variables (`src/anndata/_core/raw.py`)
- Unused factor levels are removed from obs and var columns when `remove_unused_categories` is on (`anndata.py:1093-1117`), and the matching `uns[["<col>_colors"]]` entries are subset to match, as in Python
- Sparse format is preserved

## Raw

Reference: `src/anndata/_core/raw.py`.

- An R6 class holding `X`, `var` and `varm`, with observations shared with the parent (`obs_names`, `n_obs` come from the parent)
- Fields: `X`, `var`, `varm`, `var_names`, `obs_names`, `n_obs`, `n_vars`, `shape`
- `raw[i, j]` subsets the Raw (used by `adata$raw[, "gene"]$X`)
- `raw$to_adata()` returns an `AnnData` built from the Raw and the parent's obs (`raw.py:187-200`)
- `raw$copy()`

## Methods

Each method matches the referenced Python method's behaviour, errors and warnings.

| R | Python reference | Notes |
| - | ---------------- | ----- |
| `copy()` | `anndata.py:1447` | Deep copy, independent of the original. `filename` errors until `backed`. |
| `transpose()`, `t(adata)` | `anndata.py:1248` | Swaps obs/var, obsm/varm and obsp/varp, transposes X and layers, drops raw, keeps uns |
| `to_df(layer = NULL)` | `anndata.py:1284` | Returns a dense `data.frame` (obs_names as row names, var_names as column names), erroring on duplicate names where R requires uniqueness |
| `obs_vector(k, layer = NULL)` | `anndata.py:1325` | Column `k` of obs, or the values of variable `k` across observations |
| `var_vector(k, layer = NULL)` | `anndata.py:1356` | Column `k` of var, or the values of observation `k` across variables |
| `obs_keys()`, `var_keys()`, `obsm_keys()`, `varm_keys()`, `uns_keys()` | `anndata.py:946-1000` | Character vectors |
| `obs_names_make_unique()`, `var_names_make_unique()` | `anndata.py:1578-1589` | See above |
| `strings_to_categoricals(df = NULL)` | `anndata.py:1170` | Converts character columns with fewer unique values than rows to factors, in place on obs and var (or on `df`), with Python's messages |
| `rename_categories(key, categories)` | `anndata.py:1118` | Renames levels of an obs/var factor, also renaming entries in `uns` that Python renames |

Python's `__eq__` raises `NotImplementedError` (`anndata.py:581-588`).
`==` and other comparison operators on `AnnData` raise an equivalent classed error.

## Printing

`print(adata)` and `format(adata)` reproduce Python's `__repr__` exactly (`anndata.py:562-579`).
For example:

```
AnnData object with n_obs × n_vars = 100 × 50
    obs: 'cell_type', 'n_genes'
    var: 'gene_ids'
    uns: 'neighbors'
    obsm: 'X_pca'
    layers: None (.X), 'counts'
    obsp: 'connectivities'
```

- The Slot order, quoting and separators match Python's `iter_outer` order.
  Read it from the reference and confirm it with a Python-generated expected output.
- `layers` lists the X entry as `None (.X)`, exactly as Python does, in Python's key order
- Empty Slots are omitted
- The `View of ` prefix and ` backed at '<file>'` suffix are added by later sub-projects

## Errors and warnings

Every error and warning raised by the Python code paths referenced above has an R counterpart raised under the same conditions, as classed conditions following the conventions in `foundations`.
Tests assert condition classes.

## Required tests

- Construction from every accepted input form, including `X` as a data frame and shape inference with no X
- Default names are `"0"`...`"n-1"`
- Every validation error and warning listed above, by class
- Subsetting by positive, negative, logical and character indices on each axis, with repeats and reordering, and checks that every Slot is subset correctly (including obsp, raw and uns)
- Unused-category removal and its setting
- Duplicate names: warnings, character indexing taking the first match, and `make_unique` cases including collisions and `NA`
- Sparse format preservation through construction, subsetting, copy and transpose
- On-disk dtype metadata surviving subsetting, copy and transpose (using a test double for the metadata until `h5ad-io` defines it)
- Reference semantics: `b <- a` aliases and `a$copy()` does not
- Printing matches Python's repr for a set of objects.
  Expected strings come from the Python reference environment (generated once and committed as fixtures).
- Each method in the table, including its documented errors

## Acceptance criteria

- Everything in scope is implemented and documented
- `scripts/check.sh` passes
- Behavioural tests compare against Python where there is an observable output (printing, make_unique results, `strings_to_categoricals` results), using committed Python-generated expectations
