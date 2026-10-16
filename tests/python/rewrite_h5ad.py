"""Read h5ad files with anndata and write them back, for R -> Python -> R tests.

Usage: rewrite_h5ad.py <in.h5ad> <out.h5ad> [<in.h5ad> <out.h5ad> ...]

Several pairs share one process because importing anndata is slow. Every pair
is attempted, failures are reported on stderr and make the exit status
non-zero.
"""

import sys
import traceback

import anndata


def rewrite(in_path, out_path):
    anndata.read_h5ad(in_path).write_h5ad(out_path)


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
