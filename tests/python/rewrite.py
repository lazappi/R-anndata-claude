"""Read an Element with anndata and write it back, for R -> Python -> R tests.

Usage: rewrite.py <in.h5> <out.h5>

The Element is at the key `x` of both files (as `write_elem` in the fixtures).
"""

import sys

import h5py
from anndata.io import read_elem, write_elem


def main(in_path, out_path):
    with h5py.File(in_path, "r") as src, h5py.File(out_path, "w") as dst:
        write_elem(dst, "x", read_elem(src["x"]))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
