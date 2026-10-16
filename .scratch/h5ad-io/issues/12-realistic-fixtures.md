# Realistic and compressed fixtures

Status: done
Type: task
Blocked by: 11

## What

Add the `gen_adata` realistic object restricted to supported encodings (`src/anndata/tests/helpers.py:304`) and its gzip and lzf variants to the fixture generator, and complete any remaining fixture coverage from the spec's fixtures list.
Run the full three-direction round trip over every fixture in `tests/testthat/fixtures/h5ad/` as one parameterised suite, and the R → R round trip for every supported R value class.

## Acceptance criteria

- Every case in the spec's fixtures list exists and is covered
- Writing every unencodable value class is tested with the correct path in the error
- Fixture freshness test passes
- `scripts/check.sh` passes

## Comments

2026-10-16: Added `realistic`, `realistic_csc`, `realistic_gzip` and `realistic_lzf` fixtures from `gen_adata` (20 x 10, seeded).
`awkward` is not in the uv environment, so `gen_awkward` is stubbed in `_realistic_adata()` and the awkward, dask and `csr_array` entries are dropped.
With `sparse_fmt="csc"` gen_adata keeps no csr-typed obsm, varm or layers entries, so `realistic_csc` only differs in X.
The four are in `adata_fixture_names`, so the existing Python -> R -> Python test covers them, with `/uns/O_recarray` exempt from dtype checks (ADR 0005) and its values compared separately.
New tests: Python -> R expectations for the realistic files, R -> Python -> R with no compression, gzip and lzf, every unencodable class by path in `uns` (top level and nested), unencodable values in `obs`, `var`, `raw` and a `uns` data frame, and an R -> R round trip of `uns` values of every supported R class.
Lists are refused by `abort_unwritable` and carry no `r_class`, only a reason in the message.
