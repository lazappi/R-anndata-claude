# anndata.claude

An R port of Python anndata (reference release 0.13.4) for annotated
data matrices and their on-disk formats.

## Language

### The object

**AnnData**: An annotated data matrix of n_obs observations by n_vars
variables, with aligned annotations and unstructured metadata. *Avoid*:
SingleCellExperiment, Seurat object, dataset

**Observation**: A row of an AnnData, usually a cell. *Avoid*: sample,
column

**Variable**: A column of an AnnData, usually a gene or feature.
*Avoid*: feature, row

**Slot**: One named component of an AnnData: X, obs, var, obsm, varm,
obsp, varp, layers, uns or raw. *Avoid*: field, attribute, assay

**obs_names / var_names**: The string identifiers of observations and
variables, which may contain duplicates. *Avoid*: rownames, colnames,
barcodes

**Aligned mapping**: A slot holding named elements whose dimensions must
match n_obs and/or n_vars (obsm, varm, obsp, varp, layers).

**uns**: The slot holding unstructured metadata as a nested mapping of
arbitrary encodable values.

**View**: An AnnData produced by subsetting that shares data with its
parent until modified, when it becomes an independent copy. *Avoid*:
slice, subset object

**raw**: A frozen copy of X, var and varm kept from before variable
filtering, sharing observations with its parent.

### On disk

**Element**: A single stored value in a file (array, sparse matrix,
dataframe, mapping or scalar) identified by its path.

**Encoding type**: The `encoding-type` attribute naming how an Element
is stored, such as `csr_matrix`, `dataframe` or `categorical`.

**Encoding version**: The `encoding-version` attribute giving the
version of an Encoding type’s layout.

**On-disk dtype**: The exact storage type of an Element’s data
(e.g. float32, int64, uint8), which R may not represent natively.

**Round trip**: Reading a file and writing it back (R to R, Python to R
to Python or R to Python to R) so that every Element keeps its Encoding
type, Encoding version, On-disk dtype and values, and the object read is
equal whichever language read or wrote it. *Avoid*: conversion, export

**Structural equivalence**: Two Stores (of the same or different
formats) with the same tree of groups and arrays, attributes, Encoding
types and versions, On-disk dtypes, shapes and values, regardless of
byte layout. *Avoid*: identical files

**Store**: A file or directory holding an AnnData on disk: an h5ad file
or a zarr store (v2 or v3). *Avoid*: container

**Shard**: A zarr v3 file holding many chunks of one array with an
index, written by default by Python (`auto_shard_zarr_v3`). Shard and
chunk layout are not part of Structural equivalence.

**Consolidated metadata**: All of a zarr store’s group and array
metadata collected in one place (`.zmetadata` in v2, the root
`zarr.json` in v3) so it can be read at once.

**Reference implementation**: Python anndata at the pinned release, the
only source of truth for behaviour.
