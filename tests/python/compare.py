"""Check that two h5ad files read as equal AnnData objects.

Usage: compare.py <a.h5ad> <b.h5ad>

Exits non-zero and prints the difference on failure.
"""

import sys

import anndata
from anndata.tests.helpers import assert_equal


def main(a_path, b_path):
    a = anndata.read_h5ad(a_path)
    b = anndata.read_h5ad(b_path)
    try:
        assert_equal(a, b)
    except AssertionError as err:
        print(f"{a_path} and {b_path} differ:\n{err}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
