# concat: aligned mappings, pairwise and raw

Status: done
Type: task
Blocked by: 03

## What

obsm, varm, obsp, varp with `pairwise`, and `raw` as Python treats it.

## Acceptance criteria

- Its rows of the concat table pass
- The full check (`scripts/check.sh --package` and `--tests`) passes

## Comments

2026-10-22: Added `pairwise`, obsm/varm/obsp/varp and `raw` to `concat()` (`R/concat-mappings.R`), every non-error table row passes (`test-concat-mappings.R`).
Facts for later runs:

- The axis mapping reuses `concat_arrays()` with synthetic column names (`"1"`, `"2"`, ...), so inner cuts to the narrowest width and outer pads to the widest with the fill. Data frames go through `concat_axis_annotation()`, and a frame mixed with an array raises `anndata_unsupported_value_error`
- The other axis mapping is reindexed (`reindex_array()`, NaN rows for dense and empty for sparse) then merged with a `same_type = FALSE` strategy. A custom `merge` function is called for both the frames and the mappings, as in Python
- `pairwise = TRUE` gives a block diagonal CSR (`concat_pairwise_mapping()`), an object lacking the key adds an empty bool block
- `raw` is a recursive `concat()` of `AnnData(X = raw$X, obs = names only, var = raw$var, varm = raw$varm)`, so its `var` columns and `varm` follow `merge` (empty by default). Python drops raw when the result has 0 observations (an `AnnData` of length 0 is falsy), and warns (`anndata_missing_raw_warning`) when only some objects have raw
- `sparse_from_triplets()` is the shared CSR builder
