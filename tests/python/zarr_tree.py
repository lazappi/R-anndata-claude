"""Print a JSON description of every group and array in a zarr store.

Usage: zarr_tree.py <store> [<store> ...]

The output has the shape of h5_tree.py (path, kind, attributes, and for arrays
the dtype, shape and a digest of the values), so a zarr store and an h5ad file
can be compared. Chunk shape, codecs, shard layout, fill value and the zarr
format are left out on purpose, because Structural equivalence ignores them.
Attribute types are the JSON types, because zarr does not store more.
A `null` Element (a 0-d bool array in zarr) is described like h5py describes
the null dataspace, so it matches an h5ad file.
"""

import json
import sys
import warnings
from pathlib import Path

# `-I` removes the script directory from the path
sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np  # noqa: E402
import zarr  # noqa: E402
from h5_tree import digest_values, to_json  # noqa: E402


def json_type(value):
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, int):
        return "int"
    if isinstance(value, float):
        return "float"
    if isinstance(value, str):
        return "str"
    if isinstance(value, list):
        return "list"
    if isinstance(value, dict):
        return "dict"
    return "null" if value is None else type(value).__name__


def attributes(node):
    out = {}
    for name in sorted(node.attrs.keys()):
        value = node.attrs[name]
        out[name] = {"value": to_json(value), "type": json_type(value)}
    return out


def dtype_text(array):
    dtype = array.dtype
    if getattr(dtype, "kind", None) == "T" or dtype == np.dtype("O"):
        return "string(variable, utf-8)"
    return str(dtype)


def describe(path, node):
    attrs = attributes(node)
    if isinstance(node, zarr.Group):
        return {"path": path, "attrs": attrs, "kind": "group"}
    out = {"path": path, "attrs": attrs, "kind": "dataset"}
    if attrs.get("encoding-type", {}).get("value") == "null":
        out.update(dtype="float32", shape=None, digest="empty", chunks=None)
        return out
    values = node[...]
    if isinstance(values, np.ndarray) and values.dtype.kind == "T":
        values = values.astype(object)
    out.update(
        dtype=dtype_text(node),
        shape=list(node.shape),
        digest=digest_values(values),
        # zarr-python's chunks, the inner chunk shape of a sharded array
        chunks=None if len(node.shape) == 0 else list(node.chunks),
    )
    return out


def tree(path):
    root = zarr.open(path, mode="r")
    nodes = [describe("/", root)]
    if isinstance(root, zarr.Group):
        for name, node in root.members(max_depth=None):
            nodes.append(describe("/" + name, node))
    nodes.sort(key=lambda n: n["path"])
    return nodes


def main(paths):
    warnings.simplefilter("ignore")
    # One store prints its list of nodes, several print one list per store
    if len(paths) == 1:
        print(json.dumps(tree(paths[0])))
    else:
        print(json.dumps([tree(path) for path in paths]))


if __name__ == "__main__":
    main(sys.argv[1:])
