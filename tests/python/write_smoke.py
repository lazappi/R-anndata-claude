"""Write tiny h5ad files for the comparison helper smoke tests.

Usage: write_smoke.py <outdir>

Writes a.h5ad, same.h5ad (identical to a) and changed.h5ad (X stored as
float64 instead of float32) and different.h5ad (different X values).
"""

import sys
from pathlib import Path

import anndata
import numpy as np


def make(dtype, offset=0):
    return anndata.AnnData((np.arange(6) + offset).astype(dtype).reshape(2, 3))


def main(outdir):
    outdir = Path(outdir)
    make(np.float32).write_h5ad(outdir / "a.h5ad")
    make(np.float32).write_h5ad(outdir / "same.h5ad")
    make(np.float64).write_h5ad(outdir / "changed.h5ad")
    make(np.float32, offset=1).write_h5ad(outdir / "different.h5ad")


if __name__ == "__main__":
    main(sys.argv[1])
