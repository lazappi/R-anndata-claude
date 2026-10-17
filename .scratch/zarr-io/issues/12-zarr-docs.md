# zarr documentation

Status: done
Type: task
Blocked by: 08

## What

Add a zarr section to the vignette (writing and reading a store, and moving it to Python and back, Python code shown but not evaluated), and check that every new export is documented and in NEWS.

## Acceptance criteria

- The vignette builds with the zarr section
- `scripts/check.sh` passes

## Comments

2026-10-17: Added "Write and read zarr" and "Move a zarr store to Python and back" sections to the vignette (Python chunks not evaluated).
`read_zarr`, `write_zarr`, `adata$write_zarr` and the settings were already documented and in NEWS.
The vignette says writing zarr v2 is unsupported until zarr-io/11 (blocked, needs-info) is settled.
