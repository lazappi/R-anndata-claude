#!/usr/bin/env bash
# Regenerate tests/testthat/fixtures/ from the Python reference environment
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/tests/testthat/fixtures"

mkdir -p "$DEST"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/generate_fixtures.py" "$DEST"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/make_unique_cases.py" "$DEST/make_unique_cases.json"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/categorical_cases.py" "$DEST/categorical_cases.json"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/repr_cases.py" "$DEST/repr_cases.json"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/unwriteable_cases.py" "$DEST/unwriteable_cases.json"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/view_cases.py" "$DEST/view_cases.json"
# zarr stores are packed into one archive, because R CMD check notes the hidden
# files (.zarray) and the long paths of a zarr directory tree in a package
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/generate_zarr_fixtures.py" "$STAGE/zarr"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/zarr_encoding_table.py" "$STAGE/zarr" "$ROOT/.scratch/zarr-io/encoding-table.md"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/pack_zarr_fixtures.py" "$STAGE/zarr" "$DEST/zarr-fixtures.tar.gz"
echo "Regenerated fixtures in $DEST"
