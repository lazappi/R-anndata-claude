# Backed reading and the file manager

Status: done
Type: task
Blocked by: 01

## What

`read_h5ad(backed = )`, `adata$file` (`open()`, `close()`, `is_open`, `filename`), `isbacked`, the `filename` getter, the print suffix, the finalizer and read-only or read-write opening (spec "Decisions" and "Behaviour").
X and `raw$X` stay on disk (temporarily as the plain HDF5 handle until tickets 03 and 04 add the classes), and every other Slot is read into memory.

## Acceptance criteria

- The reading, closing and printing rows of the operations table pass, and the handle closes after `close()` and garbage collection
- `scripts/check.sh` passes

## Comments

2026-10-17: Added `R/backed.R` (`file_manager_class`, placeholder `backed_x`), `read_h5ad(backed = )`, `adata$file`/`isbacked`/`filename`, the print suffix and `tests/testthat/test-backed-file.R` (table-driven, helpers in `helper-backed.R`).
- `backed_x` is an S3 list (manager, path, shape, encoding, dtype) with `dim()`, found through the manager so it survives `close()`. Tickets 03/04 replace it with the dense and sparse classes. `[` is not implemented yet, so Views, `copy()` and writing of a backed object are untouched (tickets 03 to 05)
- Reopen on access hooks: the aligned mapping `get()` (X and `layers[[NA]]`) and `raw$X`. Slots in memory never reopen the file
- Only modes `"r"` and `"r+"` open (Python also allows `w`, `a` and others, `w` would truncate the file). `file$get/set/remove/has/keys` stand in for `file[key]`, and `set`/`remove` in `"r"` mode raise `anndata_read_only_error`
- Backed repr lists `None (.X)` first among layers, in memory last (Python differs)
- The constructor's `filename`/`filemode` and the `filename<-` setter are still unsupported (ticket 05)
- Gotchas: a new S3 method (`dim.backed_x`) is only seen by base internals such as `nrow()` after `devtools::document()` registers it. The R6 finalizer must be private
