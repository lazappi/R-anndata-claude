"""Read h5ad files with anndata and write them back, for R -> Python -> R tests.

Usage: rewrite_h5ad.py <in.h5ad> <out.h5ad> [<in.h5ad> <out.h5ad> ...]

Zarr stores work too, a directory is read as one and an output ending in .zarr
is written as one, so this also converts between the formats.

Several pairs share one process because importing anndata is slow. Every pair
is attempted, failures are reported on stderr and make the exit status
non-zero.
"""

import os
import sys
import traceback

import anndata


def rewrite(in_path, out_path):
    # A directory is a zarr store, and an output ending in .zarr is written as one
    if os.path.isdir(in_path):
        adata = anndata.read_zarr(in_path)
    else:
        adata = anndata.read_h5ad(in_path)
    if out_path.endswith(".zarr"):
        adata.write_zarr(out_path)
    else:
        adata.write_h5ad(out_path)


def main(paths):
    if len(paths) == 0 or len(paths) % 2 != 0:
        print("usage: rewrite_h5ad.py <in.h5ad> <out.h5ad> [...]", file=sys.stderr)
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
