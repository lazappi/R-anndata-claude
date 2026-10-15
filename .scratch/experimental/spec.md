# Experimental

Status: needs-triage

Stub spec, to be grilled into a full spec before tickets are written.
Sub-project 11 of the roadmap (`.scratch/roadmap/spec.md`).
Each item may become its own sub-project when grilled.

## Goal

Port the remaining experimental and extension features of Python anndata where they make sense in R.

## Scope

- `concat_on_disk()` (`src/anndata/experimental/merge.py`)
- `AnnCollection` (`src/anndata/experimental/multi_files/_anncollection.py`)
- Awkward arrays (`awkward-array` encoding, `methods.py:990-1037`, fileformat `AwkwardArrays`)
- `acc` accessors (`src/anndata/acc/`, `docs/accessors.rst`), including `AnnData` indexing and `__contains__` with accessor references
- Extension namespaces (`register_anndata_namespace`, `src/anndata/_core/extensions.py`)

## Excluded

- `AnnLoader` and pytorch (roadmap non-goal)

## Open questions

- Is there an R representation of awkward arrays that can round trip?
- How should extension namespaces map onto R6 classes?
