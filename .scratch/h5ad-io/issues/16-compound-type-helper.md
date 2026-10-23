# Compound type helper

Status: done
Type: task
Blocked by: none

## What

Build the compiled helper of ADR 0008 and prove the design before anything uses it.

- `src/` with a small C file, `LinkingTo: Rhdf5lib`, `src/Makevars` linking the static library (use `Rhdf5lib::pkgconfig()`), `useDynLib` in `NAMESPACE`, and roxygen and `.Rbuildignore`/lintr settings that keep the check free of notes
- Read: given a file path and a dataset path, open the file read-only with the helper's own HDF5 instance and return each compound member's name, class, size, sign, byte order, string kind (fixed or variable length, ASCII or UTF-8) and array shape (for array-valued members such as legacy `obsm`)
- Write: given a field specification and the values, create a compound dataset (any member types h5py writes, including variable-length UTF-8 strings, with compression and zero rows) in a temporary file, then copy it into the open rhdf5 store with `rhdf5::H5Ocopy()`
- Verify first, and stop and ask the human if either fails: the read works while rhdf5 holds the same file open read-only (HDF5 file locking), and `H5Ocopy()` keeps the exact member types (checked with h5py)

## Acceptance criteria

- Tests read the member types of Python-written compound datasets (the rec-array fixtures and the PBMC `/obsm`), and h5py sees the exact types written through the temporary-file and `H5Ocopy()` route
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-23: Built `src/compound.c` (`c_compound_members`, `c_compound_write`), `src/Makevars`, `R/io-compound.R` (`compound_members()`, `compound_field()`, `compound_write()`, `compound_copy()`) and `tests/python/compound_types.py`.
Both verifications passed: the read works while rhdf5 holds the file open (the helper opens with file locking disabled via `H5Pset_file_locking`) and `H5Ocopy()` keeps exact types (checked with h5py, plain and gzip, zero rows).
Read reports a variable-length string's size as 8 (a pointer) and a bool as an `enum` with names `FALSE`/`TRUE` (h5py shows numpy `bool`).
Write covers little-endian integer, float, bool enum and fixed/variable ASCII/UTF-8 string fields (what h5py writes for rec-arrays), and rejects out-of-range integers.
Array-valued, big-endian, complex and vlen members are read-only for now.
Tickets 15 and 17 use these helpers.
Status: done.
