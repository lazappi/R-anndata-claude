"""Check that pairs of h5ad files read as equal AnnData objects.

Usage: compare.py <a.h5ad> <b.h5ad> [<a.h5ad> <b.h5ad> ...]

Several pairs share one process because importing anndata is slow. Every pair
is compared, the differences are printed on stderr and make the exit status
non-zero.
"""

import sys

import anndata
from anndata.tests.helpers import assert_equal


def compare(a_path, b_path):
    a = anndata.read_h5ad(a_path)
    b = anndata.read_h5ad(b_path)
    try:
        assert_equal(a, b)
    except AssertionError as err:
        print(f"{a_path} and {b_path} differ:\n{err}", file=sys.stderr)
        return 1
    return 0


def main(paths):
    if len(paths) == 0 or len(paths) % 2 != 0:
        print("usage: compare.py <a.h5ad> <b.h5ad> [...]", file=sys.stderr)
        return 2
    status = 0
    for a_path, b_path in zip(paths[0::2], paths[1::2]):
        status |= compare(a_path, b_path)
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
