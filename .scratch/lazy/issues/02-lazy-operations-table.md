# Lazy operations table

Status: done
Type: task
Blocked by: none

## What

Write `tests/python/lazy_cases.py` and generate the expected behaviour table (spec "Expected behaviour table"), registered in `scripts/regenerate-fixtures.sh` with a hash-based freshness test like the other tables.

## Acceptance criteria

- The table covers every operation listed in the spec
- `scripts/check.sh` passes

## Comments

2026-10-18: `tests/python/lazy_cases.py` writes `tests/testthat/fixtures/lazy_cases.json` (sections `read_lazy`, `read_elem_lazy`, `operations`, `dask_chunks`, rows keyed by `h5ad`, `zarr_v3`, `zarr_v2`), registered in `scripts/regenerate-fixtures.sh` and `generator_inputs()`, guarded by `test-lazy.R`.
Python facts the later tickets must follow:
- Writing a lazy AnnData raises `NotImplementedError` (`Dataset2D` unsupported), so writing goes through `to_memory()` (rows `write_*_after_to_memory`)
- `Dataset2D` has no `.loc`, `read_elem_lazy` of a dict or scalar raises `IORegistryError`
- Sparse `chunks` on the minor axis and a wrong-length `chunks` raise `ValueError`
- Lazy categorical and masked arrays cannot be indexed directly (xarray error), they are realised through the lazy frame
- Lazy frame column order varies between runs in Python, so the table sorts it
- Big arrays record `values_sum` and `values_head`, not all values
Fixtures were regenerated because `uv.lock` changed (xarray), which also touched `realistic*.h5ad` and the zarr archive.
