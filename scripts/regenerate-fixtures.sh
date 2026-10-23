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
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/backed_cases.py" "$DEST/backed_cases.json"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/lazy_cases.py" "$DEST/lazy_cases.json"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/concat_cases.py" "$DEST/concat_cases.json"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/other_formats_cases.py" "$DEST/other_formats_cases.json"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/encoding_table.py" "$DEST" "$ROOT/.scratch/h5ad-io/encoding-table.md"
# zarr stores are packed into one archive, because R CMD check notes the hidden
# files (.zarray) and the long paths of a zarr directory tree in a package
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/generate_zarr_fixtures.py" "$STAGE/zarr"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/zarr_encoding_table.py" "$STAGE/zarr" "$ROOT/.scratch/zarr-io/encoding-table.md"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/pack_zarr_fixtures.py" "$STAGE/zarr" "$DEST/zarr-fixtures.tar.gz"
# Legacy fixtures come from real old releases (each in its own uv environment),
# so legacy_fixtures.py needs no project, then 0.13.4 reads them for the table
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/legacy_fixtures.py" "$DEST"
uv run --project "$ROOT/tests/python" python -I "$ROOT/tests/python/legacy_cases.py" "$DEST" "$DEST/legacy_cases.json"
(cd "$ROOT" && Rscript scripts/write-generator-hashes.R)
echo "Regenerated fixtures in $DEST"
