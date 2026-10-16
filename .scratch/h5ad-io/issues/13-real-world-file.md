# Real-world file test

Status: done
Type: task
Blocked by: 12

## What

Download scanpy's `pbmc3k_processed` in a test that skips offline, read it, round trip it through R and check Structural equivalence with the original.
Fix or record in `fix_plan.md` anything it finds.

## Acceptance criteria

- The test passes with network and skips cleanly without
- `scripts/check.sh` passes

## Decisions (human, 2026-10-16)

- Keep the fix in `R/io-sparse.R` that sorts unsorted indices on read, with a unit test using a small file with unsorted indices (ADR 0006).
  Compare `/raw/X` (and any other sparse Element with unsorted indices in the original) by value, not by Structural equivalence.
- Exempt `/uns/rank_genes_groups` with `rec_array_paths` and check it with `expect_rec_array_values_equal()`, as the other rec-array tests do (ADR 0005, h5ad-io/15)
- The test may download a different file from scanpy's `pbmc3k_processed` as long as the ticket comment names the source

## Comments

2026-10-16: done.
- Source: `https://raw.githubusercontent.com/chanzuckerberg/cellxgene/main/example-dataset/pbmc3k.h5ad` (the PBMC 3k processed example), downloaded with `utils::download.file()`, skipping offline, on CRAN or with `ANNDATA_SKIP_NETWORK=true`.
  I could not confirm it is byte-identical to scanpy's `pbmc3k_processed`.
- The download is in a legacy format that `read_h5ad()` rejects, so the test has Python rewrite it with the current encodings and uses that file as the original (recorded in `fix_plan.md` Discovered).
- Found and fixed: sparse matrices with unsorted indices crashed the read (ADR 0006), now sorted on read with a unit test for CSR and CSC in `test-io-sparse.R`.
- Per the decisions: `/raw/X/data` and `/raw/X/indices` skip the digest comparison (new `sorted_paths` argument of the equivalence helpers, any other unsorted sparse Element would still fail) and `raw$X` is compared by value.
  `/uns/rank_genes_groups/{names,scores}` are rec-arrays compared with `expect_rec_array_values_equal()`.
- `expect_python_equal()` is not used, because Python would compare the `scores` field dtype (`<f4` against `<f8`, ADR 0005), so the test checks Python can read the written file by rewriting it instead.
