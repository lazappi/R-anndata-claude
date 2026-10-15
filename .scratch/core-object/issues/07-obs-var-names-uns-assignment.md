# obs, var, names and uns assignment

Status: done
Type: task
Blocked by: 03

## What

Active bindings for obs, var, obs_names, var_names and uns (`anndata.py:752-830`, `:769-819`).

- `adata$obs <- df` and `adata$var <- df` convert as in construction, check the row count and keep current names unless the value brings its own
- `adata$obs_names <- x` and `adata$var_names <- x` check length, coerce to character and apply the uniqueness warning
- The index name is preserved
- `adata$uns <- list(...)` must be a named list or empty, and `adata$uns[["k"]] <- v` sets one entry

## Acceptance criteria

- Each branch is tested by condition class, with Python-confirmed behaviour
- `scripts/check.sh` passes

## Comments

2026-10-15: Implemented `obs`, `var`, `obs_names`, `var_names` and `uns` active bindings in `R/anndata.R` (tests in `tests/testthat/test-assignment.R`, oracle script `.ralph/oracle/setters.py`).
Two deliberate deviations from the ticket text, because Python 0.13.4 behaves differently:
- Assigning `obs`/`var` without its own names resets names to `"0"`, `"1"`, ... (it does not keep the current names), with `anndata_implicit_modification_warning` for a `data.frame` with automatic row names. `NULL` gives an empty frame.
- Setting `obs_names`/`var_names` gives no duplicate warning (Python warns only at construction), and accepts duplicates and `NA`. A plain vector resets the index name, while assigning `obs` keeps the value's index name.
Renaming also rewrites the row names of data frames in `obsm`/`varm`, as Python does.
`uns` must be a named list or empty, `NULL` errors as in Python, and the constructor accepts `uns`.
Ticket 04 and 06 block each other (04's remaining `layers[[NA]]` item needs 06, which is blocked by 04), so a human should drop 06's `Blocked by: 04`.
