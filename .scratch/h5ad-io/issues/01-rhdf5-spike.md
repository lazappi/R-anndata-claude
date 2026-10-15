# rhdf5 capability spike

Status: ready-for-agent
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
