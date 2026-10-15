# R generics and comparison error

Status: ready-for-agent
Type: task
Blocked by: 10, 11

## What

- `dim()`, `dimnames()`, `nrow()`, `ncol()`, `length()`, `t()` and `[` methods on `AnnData`
- `==` and other comparison operators raise a classed error equivalent to Python's `NotImplementedError` (`anndata.py:581-588`)
- Package documentation covers every exported function and class

## Acceptance criteria

- Each generic is tested
- Comparison operators error with the documented class
- Everything in the core-object spec scope is implemented and documented
- `scripts/check.sh` passes

## Comments
