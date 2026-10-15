# anndata.claude

An R port of Python anndata (reference release 0.13.4) for annotated data matrices and their on-disk formats.

## Language

### The object

**AnnData**:
An annotated data matrix of n_obs observations by n_vars variables, with aligned annotations and unstructured metadata.
_Avoid_: SingleCellExperiment, Seurat object, dataset

**Observation**:
A row of an AnnData, usually a cell.
_Avoid_: sample, column

**Variable**:
A column of an AnnData, usually a gene or feature.
_Avoid_: feature, row

**Slot**:
One named component of an AnnData: X, obs, var, obsm, varm, obsp, varp, layers, uns or raw.
_Avoid_: field, attribute, assay

**obs_names / var_names**:
The string identifiers of observations and variables, which may contain duplicates.
_Avoid_: rownames, colnames, barcodes

**Aligned mapping**:
A slot holding named elements whose dimensions must match n_obs and/or n_vars (obsm, varm, obsp, varp, layers).

**uns**:
The slot holding unstructured metadata as a nested mapping of arbitrary encodable values.

**View**:
An AnnData produced by subsetting that shares data with its parent until modified, when it becomes an independent copy.
_Avoid_: slice, subset object

**raw**:
A frozen copy of X, var and varm kept from before variable filtering, sharing observations with its parent.

### On disk

**Element**:
A single stored value in a file (array, sparse matrix, dataframe, mapping or scalar) identified by its path.

**Encoding type**:
The `encoding-type` attribute naming how an Element is stored, such as `csr_matrix`, `dataframe` or `categorical`.

**Encoding version**:
The `encoding-version` attribute giving the version of an Encoding type's layout.

**On-disk dtype**:
The exact storage type of an Element's data (e.g. float32, int64, uint8), which R may not represent natively.

**Round trip**:
Reading a file and writing it back (R to R, Python to R to Python or R to Python to R) so that every Element keeps its Encoding type, Encoding version, On-disk dtype and values, and the object read is equal whichever language read or wrote it.
_Avoid_: conversion, export

**Structural equivalence**:
Two files with the same tree of groups and datasets, attributes, Encoding types and versions, On-disk dtypes, shapes and values, regardless of byte layout.
_Avoid_: identical files

**Reference implementation**:
Python anndata at the pinned release, the only source of truth for behaviour.
