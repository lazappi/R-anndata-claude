# Compound types through a compiled helper

Supersedes ADR 0005.
rhdf5 still cannot read or build the members of an HDF5 compound type (checked in 2.57.20), so rec-array field dtypes, h5py's variable-length UTF-8 fields, rec-arrays with no rows or with compression, and float32 fields in legacy compound datasets were all degraded or impossible.
A small C helper in `src/`, linked against Rhdf5lib (`LinkingTo: Rhdf5lib`), now reads compound member names and types and builds compound datasets, with no system library and no second HDF5 binding such as hdf5r.
Rhdf5lib is a static library, so the helper has its own HDF5 instance, separate from rhdf5's: HDF5 ids are never passed between them and the two never write to the same open file.
The helper reads member types by file path (read-only), and writes a compound dataset into a temporary file that rhdf5 then copies into the store with `H5Ocopy()`, which keeps the exact type.
The package gains compiled code, which is acceptable because it is not published and Bioconductor installs already need a C toolchain.
