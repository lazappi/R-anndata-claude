# Deprecation warnings

Status: ready-for-agent
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
