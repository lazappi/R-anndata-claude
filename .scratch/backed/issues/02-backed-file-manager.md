# Backed reading and the file manager

Status: ready-for-agent
Type: task
Blocked by: 01

## What

`read_h5ad(backed = )`, `adata$file` (`open()`, `close()`, `is_open`, `filename`), `isbacked`, the `filename` getter, the print suffix, the finalizer and read-only or read-write opening (spec "Decisions" and "Behaviour").
X and `raw$X` stay on disk (temporarily as the plain HDF5 handle until tickets 03 and 04 add the classes), and every other Slot is read into memory.

## Acceptance criteria

- The reading, closing and printing rows of the operations table pass, and the handle closes after `close()` and garbage collection
- `scripts/check.sh` passes

## Comments
