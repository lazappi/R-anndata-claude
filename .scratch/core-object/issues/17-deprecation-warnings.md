# Deprecation warnings

Status: done
Type: task
Blocked by: 13

## What

Python 0.13.4 marks `obs_vector`, `var_vector` and the `*_keys()` methods deprecated, and they warn when called.
core-object/13 implemented them without warnings.

- Find every method or argument the core object implements that Python 0.13.4 deprecates (ask `python-oracle`), not only the ones above
- Each warns under the same conditions as Python, with Python's message and the class mapped from Python's warning category (add the mapping to the condition helpers if the category is new)
- Each gets a lifecycle `deprecated` badge in its help page
- Internal callers do not trigger the warnings

## Acceptance criteria

- Tests assert the warning class for each deprecated method, and that non-deprecated paths do not warn
- `scripts/check.sh` passes

## Comments

2026-10-16: Done. python-oracle found the only deprecated items the R core implements are `obs_keys`, `var_keys`, `obsm_keys`, `varm_keys`, `uns_keys`, `obs_vector` and `var_vector`.
They are Python `FutureWarning`s, so `warn_deprecated()` (`R/conditions.R`) signals `anndata_deprecated_warning` plus `anndata_future_warning`, with Python's message and advice.
Every call warns, even with an invalid key.
Python also deprecates `isview`, `as_dict`, `write_loom` and the `copy_on_write_X` and `zarr_write_format` settings, none of which exist in R, so the tickets that add them must warn too.
The badge sits in a "Deprecated methods" section of the `AnnData()` help page because the R6 class is `@noRd`.
Tests of deprecated methods wrap calls in `quiet_deprecated()` (`helper-conditions.R`).
