# Backed dense X

Status: done
Type: task
Blocked by: 02

## What

The backed dense class: `dim()`, `[` with every R index form, conversion to a matrix, printing, On-disk dtype records, and Views of backed objects reading only their subset.

## Acceptance criteria

- The dense rows of the operations table pass, and every R index form matches the in-memory selection
- `scripts/check.sh` passes

## Comments

2026-10-17: Added `R/backed-dense.R` (`backed_dense` class, also `backed_x`, with `[`, `as.matrix`, `as.array`) and table-driven tests in `test-backed-dense.R` (dense `X_*` rows in both modes, every index form, dtype records, a spy showing Views read only their rows and columns, printing without reading).
- Shared helpers (`for_each_backed`, `expect_backed_state`, `backed_row`, `table_matrix`) moved into `helper-backed.R`
- Python's dense handle rejects unsorted, repeated and negative index lists, R accepts them (tested as intentional divergences). `x[i]` and `x[]` read the whole array. Item assignment rows (`X_item`) belong to ticket 05
- Only 2-D dense arrays stay on disk, higher dimensions are read into memory (Python's handle would keep them backed)
- Tooling drift, accepted by the human: roxygen2 8.1.0 (Rd files and `DESCRIPTION` kept), lintr 3.4.0 (`<<-` in `helper-python.R` replaced by an environment), rhdf5 2.57.12 (`h5read(native = TRUE)` segfaults on scalar datasets so `spike_read()` uses `native = FALSE` for them, and `H5Pset_lzf()` no longer takes `h5tid`), R 4.6 (error text `'dim'` in `test-zarr-spike.R`)
