#!/usr/bin/env bash
# Regenerate tests/testthat/fixtures/ from the Python reference environment
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/tests/testthat/fixtures"

mkdir -p "$DEST"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/generate_fixtures.py" "$DEST"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/make_unique_cases.py" "$DEST/make_unique_cases.json"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/categorical_cases.py" "$DEST/categorical_cases.json"
echo "Regenerated fixtures in $DEST"
