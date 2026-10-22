# Concatenation

Status: ready-for-agent

Sub-project 5 of the roadmap (`.scratch/roadmap/spec.md`), after `lazy`.
`concat()` combines `AnnData` objects along either axis with the same results as Python, including joins, merge strategies, labels and index handling.

Python references are relative to `.reference/anndata/`: `src/anndata/_core/merge.py` (`concat` `:1440` and the rest of the file, written as `merge.py`), `docs/tutorials/concatenation.rst`, and release notes 0.13.0 (`AnnData.concatenate` removed) and 0.13.3.

## Decisions (human, 2026-10-22)

- Expected behaviour comes from a Python-generated table of input combinations (see below), which answers whether dtypes and sparse formats match Python for every combination
- `concat()` accepts what Python accepts: in-memory objects, Views, backed objects (read into memory, as Python does) and lazily read objects (kept lazy, as Python does).
  Lazy inputs are their own final ticket, and if a lazy case cannot sensibly match Python it is recorded as a deviation rather than holding back the rest.
- `concat_on_disk` stays in `experimental`, which is low priority and gets little effort

## Scope

In:

- `concat(adatas, axis = c("obs", "var"), join = c("inner", "outer"), merge = NULL, uns_merge = NULL, label = NULL, keys = NULL, index_unique = NULL, fill_value = NULL, pairwise = FALSE)`, with Python's defaults and any warnings Python gives about them
- A named list as input, whose names become `keys`
- Merge strategies `NULL`, `"same"`, `"unique"`, `"first"` and `"only"` for the alternate-axis annotations and for `uns`, and custom merge functions (R functions in place of Python callables)
- X and layers: dense and sparse mixing, the resulting sparse format and On-disk dtype, reindexing with `fill_value` on outer joins, and Python 0.13.3's promotion of bool to nullable boolean
- obs and var, including categoricals (category order and union as Python), the index, `index_unique` and `label`
- obsm, varm, obsp and varp (`pairwise`), and `raw` as Python treats it
- Objects with no X (since 0.13.0)

Out:

- `concat_on_disk` (`experimental`)

## Expected behaviour table

`tests/python/concat_cases.py` (registered in `scripts/regenerate-fixtures.sh`, with a hash-based freshness test like the other tables) writes a JSON table to `tests/testthat/fixtures/`.
It crosses at least: dense, CSR and CSC inputs (and mixtures), several dtypes, `NULL` X, missing and differing Slots, both axes, both joins, every `merge` and `uns_merge` strategy, `label`, `keys` (and a named list), `index_unique`, `fill_value` and `pairwise`.
For each case it records the result's values, On-disk dtypes, sparse format, names, categories and any warning or error (class and message).
Keep the number of Python starts small: build all cases in one script run.

## Required tests

- Every row of the concat table
- Views and backed inputs give the same results as their in-memory equivalents
- Lazy inputs give lazy results whose realised values equal the in-memory result
- A concatenated object written by R is Structurally equivalent to Python's result written by Python, for a representative set of cases

## Acceptance criteria

- Every row of the concat table passes
- The full check (`scripts/check.sh --package` and `--tests`) passes
