"""Writes a legacy h5ad whose obsm and varm are compound datasets.

Old scanpy stored `obsm` as a structured array with array-valued fields.
Usage: write_compound_obsm.py <out.h5ad>
"""

import sys

import h5py
import numpy as np

path = sys.argv[1]
obsm = np.zeros(
    3, dtype=[("X_pca", "<f4", (2,)), ("X_umap", "<f8", (3,))]
)
obsm["X_pca"] = np.arange(6, dtype="f4").reshape(3, 2)
obsm["X_umap"] = np.arange(9, dtype="f8").reshape(3, 3) / 2
varm = np.zeros(2, dtype=[("PCs", "<f8", (2,))])
varm["PCs"] = np.arange(4, dtype="f8").reshape(2, 2)
obs = np.zeros(3, dtype=[("index", "S2"), ("n", "<f8")])
obs["index"] = [b"a", b"b", b"c"]
var = np.zeros(2, dtype=[("index", "S2"), ("m", "<f8")])
var["index"] = [b"g", b"h"]

with h5py.File(path, "w") as f:
    f["X"] = np.arange(6, dtype="f8").reshape(3, 2)
    f["obs"] = obs
    f["var"] = var
    f["obsm"] = obsm
    f["varm"] = varm
    # Datasets of `uns` for the other legacy layouts
    uns = f.create_group("uns")
    uns["one_fixed"] = np.array([b"abc"], dtype="S3")
    uns["one_vlen"] = np.array(["abc"], dtype=h5py.string_dtype())
    uns["three_fixed"] = np.array([b"a", b"b", b"c"], dtype="S1")
    uns["plain"] = np.array(
        [(1.0, 2), (3.0, 4)], dtype=[("a", "<f8"), ("b", "<i4")]
    )
    uns["mixed"] = np.zeros(2, dtype=[("m", "<f8", (2,)), ("s", "<f8")])
    uns["ambiguous"] = np.zeros(2, dtype=[("p", "<f4", (2,)), ("q", "<f8", (2,))])
    uns["complex"] = np.array([1 + 2j, 3 + 4j], dtype="complex128")

# A second file with a compound that cannot be read exactly
if len(sys.argv) > 2:
    with h5py.File(sys.argv[2], "w") as f:
        f["big"] = np.array([(2**60, np.zeros(2))], dtype=[("v", "<i8"), ("w", "<f8", (2,))])
