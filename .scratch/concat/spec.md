# Concatenation

Status: needs-triage

Stub spec, to be grilled into a full spec before tickets are written.
Sub-project 5 of the roadmap (`.scratch/roadmap/spec.md`).

## Goal

`concat()` combines `AnnData` objects along either axis with the same results as Python, including joins, merge strategies, labels and index handling.

## Scope

- `concat(adatas, axis = c("obs", "var"), join = c("inner", "outer"), merge, uns_merge, label, keys, index_unique, fill_value, pairwise)`
- Named list input (names become `keys`)
- Merge strategies `NULL`, `"same"`, `"unique"`, `"first"` and `"only"`, for the alternate-axis annotations and for uns
- Reindexing with fill values, including Python 0.13.3's promotion of bool to nullable boolean on outer joins
- Sparse/dense mixing rules and the resulting dtypes
- Objects with no X (supported since 0.13.0)

## Python references

- `src/anndata/_core/merge.py:1440` (`concat`) and the rest of `merge.py`
- `docs/tutorials/concatenation.rst`
- Release notes 0.13.0 (`AnnData.concatenate` removed) and 0.13.3

## Open questions

- Does the output dtype and sparse format match Python for every combination of input types?
  A fixture matrix of inputs is needed.
- `concat_on_disk` belongs to `experimental`. Confirm.
