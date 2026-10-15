#!/usr/bin/env bash
# Fetch the pinned Python anndata reference implementation into .reference/anndata
set -euo pipefail

TAG="0.13.4"
COMMIT="a487b81d38d4bfe7c7d76f01eed72a8622665c65"
DEST="$(cd "$(dirname "$0")/.." && pwd)/.reference/anndata"

if [ -d "$DEST/.git" ] && [ "$(git -C "$DEST" rev-parse HEAD)" = "$COMMIT" ]; then
    echo "Reference anndata $TAG already present at $DEST"
    exit 0
fi

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TAG" https://github.com/scverse/anndata "$DEST"

if [ "$(git -C "$DEST" rev-parse HEAD)" != "$COMMIT" ]; then
    echo "Tag $TAG does not point at expected commit $COMMIT" >&2
    exit 1
fi

echo "Fetched reference anndata $TAG to $DEST"
