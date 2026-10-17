# Views

Status: ready-for-agent

Sub-project 4 of the roadmap (`.scratch/roadmap/spec.md`), queued after `zarr-io`.
`adata[i, j]` returns a View: an `AnnData` that shares data with its parent and becomes an independent object (copy-on-write) when modified, matching Python's view semantics.

Python references are relative to `.reference/anndata/src/anndata/_core/`: `anndata.py` (`_init_as_view` `:292-353`, `_init_as_actual` `:354`, the Slot properties and setters, `transpose` `:1248-1262`), `views.py` (`view_update` `:44-67`, `_SetItemMixin` `:70-90`, the view classes), `aligned_mapping.py` (`AlignedView` `:139-208`) and `index.py` (index normalisation and composition).

## Decisions (human, 2026-10-16)

- Match Python's mix of lazy and snapshot parts exactly: X, layers, obsm, varm, obsp and varp are subset from the parent on each access, so a View shows later changes to the parent's X, and obs, var, uns and raw are snapshots taken when the View is created
- Any assignment through a View, including nested forms (`view$X[1, 1] <- 0`, `view$obs$col <- x`, `view$layers[["a"]] <- m`, `view$uns$k <- v`), makes the View an independent object in place (`is_view` becomes `FALSE`), leaves the parent unchanged and raises `anndata_implicit_modification_warning` where Python warns
- Accessors return plain R values (a matrix, a `DataFrame`, a list), not view wrappers.
  The deviation this causes is documented: in Python `x = view.X; x[0, 0] = 1` modifies the View, while in R `x <- view$X; x[1, 1] <- 1` only changes `x`.
- Expected behaviour comes from a Python-generated table of View operations, guarded by a freshness test
- Caching, deferred sparse subsetting and memory use are implementation decisions for the agents, as long as observable behaviour matches Python

## Scope

In:

- `adata[i, j]` returns a View (replacing the MVP's independent copy, as the core-object spec anticipated)
- `adata$is_view`, the `View of ` prefix in `print()`/`format()`, and `copy()` of a View returning an independent object
- Views of X, layers, obs, var, the aligned mappings, uns and raw
- Views of Views, with indices composed against the original parent (`_resolve_idxs`), so a View's parent is never a View
- Copy-on-write on any modification, with Python's warnings
- Methods on Views behave as in Python: `transpose()` raises Python's error, writing a View to h5ad or zarr writes the subset, and the other methods follow the operations table
- A vignette paragraph on Views and the documented deviation

Out:

- Backed Views (`backed`), lazy arrays (`lazy`)

## Behaviour

- Subsetting keeps the R index semantics of the core-object spec (1-based, negative exclusion, logical, names), normalised to positions before composition
- A View holds a reference to its parent, so the parent stays alive while any View of it does, as in Python
- The lazy parts read through the parent on every access, so assigning a new X to the parent is visible in its existing Views, and the snapshot parts are not affected by later changes to the parent
- `remove_unused_categories` applies when the View is created, as in `_init_as_view` (including the `uns` colours)
- Copy-on-write follows `view_update`: the View is copied, the change applied to the copy, and the View re-initialised as actual from it
- Warnings follow Python's messages and conditions, for example "Setting element `.X` of view, initializing view as actual." and "Trying to modify attribute `.obs` of view, initializing view as actual."
- Deleting a key through a View (`view$obsm[["k"]] <- NULL`) is a modification
- Reading never warns or copies

## Expected behaviour table

`tests/python/view_cases.py` (registered in `scripts/regenerate-fixtures.sh`, like `repr_cases.py`) writes a JSON table to `tests/testthat/fixtures/`.
For each operation on a View it records whether Python warns (and the warning class and message), `is_view` afterwards, the resulting values, and whether the parent changed.
Operations cover at least: assigning and modifying each Slot (X, layers, obs, var, obsm, varm, obsp, varp, uns, raw, obs_names, var_names), nested modification, deleting keys, Views of Views, `copy()`, `transpose()`, every other public method, writing to h5ad and zarr, and changing the parent after the View is created.

## Required tests

- Every row of the operations table, with the R equivalent of each operation
- Index composition for Views of Views with every R index form
- Round trips that write Views to h5ad and zarr and compare with Python writing the same View
- The documented deviation (an extracted value does not affect the View)

## Acceptance criteria

- Every row of the operations table passes
- Subsetting returns Views everywhere, and the existing core-object and I/O tests still pass (updated only where the operations table shows Python returns a View)
- `scripts/check.sh` passes
