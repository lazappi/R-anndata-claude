# Views

Status: needs-triage

Stub spec, to be grilled into a full spec before tickets are written.
Sub-project 4 of the roadmap (`.scratch/roadmap/spec.md`).

## Goal

`adata[i, j]` returns a View that shares data with its parent and becomes an independent copy (copy-on-write) when modified, matching Python's view semantics, including `ImplicitModificationWarning`.

## Scope

- `is_view`, the `View of ` repr prefix and `copy()` on views
- Views of X, layers, obs, var, the aligned mappings, uns and raw
- Copy-on-write on any modification, with `anndata_implicit_modification_warning` raised where Python raises it
- Views of views, and indices composed against the original parent
- X copy-on-write (Python 0.13.0 made this the default and deprecated `copy_on_write_X`)
- The `transpose()` error on views

## Python references

- `src/anndata/_core/views.py` (view classes, `view_update`, `as_view`)
- `src/anndata/_core/anndata.py:292-353` (`_init_as_view`) and `:1377-1396` (`_mutated_copy`)
- `src/anndata/_core/aligned_mapping.py:139-208` (`AlignedView`)
- `src/anndata/_core/index.py` (index normalisation and composition)

## Open questions

- Should views be lazy (store indices and subset on access) or eager with a parent link?
  Python is lazy.
- How do R6 active bindings trigger copy-on-write for nested modifications such as `view$obs$col[1] <- x`, which R evaluates as get, modify and set?
- What is the memory cost of R's own copy-on-modify of large matrices, compared with Python?
- Can `Matrix` sparse subsetting be deferred efficiently?
