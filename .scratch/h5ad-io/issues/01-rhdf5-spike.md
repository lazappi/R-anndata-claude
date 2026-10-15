# rhdf5 capability spike

Status: needs-info
Type: research
Blocked by: none

## What

Confirm rhdf5 (with rhdf5filters) can read and write each of these exactly as h5py does, per the "HDF5 binding" section of the spec:

- variable-length UTF-8 string datasets and attributes
- h5py's boolean enum type
- every integer and float width, signed and unsigned
- complex numbers (h5py compound `r`/`i`)
- structured (compound) datasets for `rec-array`, including fixed-length byte and unicode fields
- 0-dimensional (scalar) datasets
- array-valued attributes such as `column-order`
- gzip and lzf compression

Where rhdf5 cannot, document the gap and propose a workaround (lower-level `H5T`/`H5D` calls).
If no workaround exists, stop and mark the ticket `needs-info`.
Also record how row-major on-disk shape maps to R `dim()`, and recommend how 64-bit integers are read (double when exact, otherwise `bit64::integer64` or a classed error).
Add `rhdf5` and `rhdf5filters` to Imports (or Suggests if the spike shows that is enough), replacing any placeholder.

## Acceptance criteria

- A findings document is committed at `.scratch/h5ad-io/rhdf5-spike.md` with a pass, gap or workaround verdict for every item above
- Each verdict is backed by a test that reads a Python-written fixture and writes a file that Python reads back
- The int64 recommendation is stated
- `scripts/check.sh` passes

## Comments

2026-10-15: Findings are in `.scratch/h5ad-io/rhdf5-spike.md`, backed by `tests/testthat/test-rhdf5-spike.R` (fixture `spike_types.h5`, read-back script `tests/python/spike_describe.py`).
Every item passes or has a tested workaround (low-level `H5T`/`H5D`/`H5A` calls, `native = TRUE` reads, bit64 reads) except `rec-array`.
The int64 recommendation is stated in the doc.

**Question for the human:** rhdf5 cannot read compound member dtypes (no `H5Tget_member_*`, `H5Tget_sign`) or write compounds with chosen widths or variable-length string members (no `H5Tinsert`).
So `rec-array` field dtypes and h5py's variable-length string fields cannot round trip.
Options are in the "rec-array (gap)" section.
Recommended: a small compiled helper in `src/` linking Rhdf5lib (no new system dependency).
Alternatives are `hdf5r` (system libhdf5, not installed) or accepting degraded `rec-array` dtypes.
This only affects h5ad-io/08 (and the rec-array parts of 04).

Dependencies: `rhdf5` stays in Imports, `bit64` and `rhdf5filters` are in Suggests until code needs them.
The placeholder `@importFrom rhdf5 h5ls` stays because no package code uses rhdf5 yet, and removing it gives an unused-Imports NOTE.
Also fixed `tests/python/h5_tree.py` digest, which was non-deterministic for compounds with variable-length strings.
