"""Write a View of an AnnData file with anndata, for Structural equivalence tests.

Usage: rewrite_view.py <obs> <var> <in> <out> [<in> <out> ...]

`obs` and `var` are comma separated 0-based positions (the same View of every
input). Inputs and outputs follow rewrite_h5ad.py (directories are zarr stores,
an output ending in .zarr is written as one). Python writes the View with its
default settings, so the output is what Python gives for `adata[obs, var]`.
"""

import os
import sys
import traceback

import anndata


def positions(text):
    return [int(i) for i in text.split(",")]


def rewrite_view(obs, var, in_path, out_path):
    if os.path.isdir(in_path):
        adata = anndata.read_zarr(in_path)
    else:
        adata = anndata.read_h5ad(in_path)
    view = adata[obs, var]
    assert view.is_view
    if out_path.endswith(".zarr"):
        view.write_zarr(out_path)
    else:
        view.write_h5ad(out_path)


def main(args):
    paths = args[2:]
    if len(args) < 4 or len(paths) % 2 != 0:
        print("usage: rewrite_view.py <obs> <var> <in> <out> [...]", file=sys.stderr)
        return 2
    obs, var = positions(args[0]), positions(args[1])
    status = 0
    for in_path, out_path in zip(paths[0::2], paths[1::2]):
        try:
            rewrite_view(obs, var, in_path, out_path)
        except Exception:
            print(f"Writing a View of {in_path} failed:\n{traceback.format_exc()}", file=sys.stderr)
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
