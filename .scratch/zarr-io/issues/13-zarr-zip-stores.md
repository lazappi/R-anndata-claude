# zip stores

Status: wontfix
Type: task
Blocked by: 08

## What

Read and write single-file `.zarr.zip` stores, which Rarr does not support (spike).
Options include unzipping to a temporary directory for reading and the `zip` package for writing.

## Acceptance criteria

- Python-written zip stores read in R and R-written ones read in Python
- `scripts/check.sh` passes

## Comments

2026-10-23 (human): wontfix, zip stores are a store-level feature for Rarr rather than anndata, so revisit if Rarr supports them.
