# Escape keys in printing like Python's repr

Status: done
Type: task
Blocked by: 15

## What

`format.AnnData` quotes keys with `quote_key()` (`R/printing.R`), but does not escape control characters as Python's `repr` does (`\n`, `\t`), see the last comment on core-object/15.

- Keys are quoted exactly as Python's `repr(str)` quotes them: escapes for control and non-printable characters, and Python's choice between single and double quotes when the key contains a quote
- Add cases with such keys to `tests/python/repr_cases.py` and regenerate the expectations

## Acceptance criteria

- Output matches Python for keys with newlines, tabs, quotes of both kinds and non-ASCII text
- `scripts/check.sh` passes

## Comments

2026-10-16: `quote_key()` now escapes like `repr(str)` through `escape_char()`: backslash, the quote in use, `\n`, `\r`, `\t`, and `\x`/`\u`/`\U` for Unicode categories C* and Z* other than a plain space.
Added an `escapes` case to `repr_cases.py` and `test-printing.R` (newline, tab, backslash, control char, nbsp, zero-width space, emoji, both quote kinds, double quote only) and regenerated the fixture.
