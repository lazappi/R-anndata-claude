# rec-array field dtypes are not preserved with rhdf5

Superseded by ADR 0008.

rhdf5 cannot inspect the fields of a compound type (no `H5Tget_member_type`, `H5Tget_member_name` or `H5Tget_sign`) or build one (no `H5Tinsert`, and `H5Tcreate` is internal).
This is true in release 2.54.1 and in the development version 2.57.20 (checked 2026-10-15).
So `rec-array` Elements keep their field names, order and values but not their field dtypes: on write, rhdf5's `data.frame` compound writer produces only int32, float64 and fixed-length ASCII string fields, where h5py writes the original widths and variable-length UTF-8 strings.
We accept this deviation from "on disk is non-negotiable" for `rec-array` only, rather than adding compiled code or a second HDF5 binding (`hdf5r`) to the MVP, and maximise compatibility within it: values round trip exactly in every direction and Python reads every R-written `rec-array`.
Restoring full fidelity, via upstream rhdf5 support, a compiled helper linked to Rhdf5lib or hdf5r, is a follow-up task (`.scratch/h5ad-io/issues/15-rec-array-dtype-fidelity.md`).
