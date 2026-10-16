"""Read Elements with anndata and write them back, for R -> Python -> R tests.

Usage: rewrite.py <in.h5> <out.h5> [<in.h5> <out.h5> ...]

The Element is at the key `x` of every file (as `write_elem` in the fixtures).
Several pairs share one process because importing anndata is slow. Every pair is
attempted, failures are reported on stderr and make the exit status non-zero.
"""

import os
import sys
import traceback

import h5py
import zarr
from anndata.io import read_elem, write_elem


def rewrite(in_path, out_path):
    # A directory is a zarr store, written with the zarr defaults (v3)
    if os.path.isdir(in_path):
        src = zarr.open_group(in_path, mode="r")
        dst = zarr.open_group(out_path, mode="w")
        write_elem(dst, "x", read_elem(src["x"]))
        return
    with h5py.File(in_path, "r") as src, h5py.File(out_path, "w") as dst:
        write_elem(dst, "x", read_elem(src["x"]))


def main(paths):
    if len(paths) == 0 or len(paths) % 2 != 0:
        print("usage: rewrite.py <in.h5> <out.h5> [<in.h5> <out.h5> ...]", file=sys.stderr)
        return 2
    status = 0
    for in_path, out_path in zip(paths[0::2], paths[1::2]):
        try:
            rewrite(in_path, out_path)
        except Exception:
            print(f"Rewriting {in_path} failed:\n{traceback.format_exc()}", file=sys.stderr)
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
