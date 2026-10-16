"""Print a JSON description of every group and dataset in an HDF5 file.

Usage: h5_tree.py <file> [<file> ...]

Each node has its path, kind, attributes (value and stored type), and for
datasets the dtype, shape and a digest of the values.
"""

import hashlib
import json
import sys

import h5py
import numpy as np


def describe_type(dtype, type_id=None):
    """Describe a stored type, distinguishing variable-length UTF-8 strings."""
    string_info = h5py.check_string_dtype(dtype)
    if string_info is not None:
        if string_info.length is None:
            return f"string(variable, {string_info.encoding})"
        return f"string(fixed {string_info.length}, {string_info.encoding})"
    if dtype.kind == "O" and type_id is not None and hasattr(type_id, "is_variable_str"):
        kind = "variable" if type_id.is_variable_str() else "fixed"
        cset = "utf-8" if type_id.get_cset() == 1 else "ascii"
        return f"string({kind}, {cset})"
    return str(dtype)


def to_json(value):
    """Convert an attribute value into plain JSON types."""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    if isinstance(value, np.ndarray):
        return [to_json(v) for v in value.tolist()]
    if isinstance(value, np.generic):
        return to_json(value.item())
    if isinstance(value, (list, tuple)):
        return [to_json(v) for v in value]
    if isinstance(value, float) and not np.isfinite(value):
        return repr(value)
    return value


def digest(dataset):
    """Hash the values of a dataset so large datasets compare cheaply."""
    return digest_values(dataset[()])


def digest_values(values):
    """Hash values read from an HDF5 dataset or a zarr array (see zarr_tree.py)."""
    sha = hashlib.sha256()
    if isinstance(values, np.ndarray) and values.dtype.kind in "OSU":
        for item in values.ravel().tolist():
            if isinstance(item, str):
                item = item.encode("utf-8")
            sha.update(bytes(item))
            sha.update(b"\0")
    elif isinstance(values, np.ndarray) and values.dtype.names is not None:
        # Compound members may hold object pointers, so hash field by field
        for name in values.dtype.names:
            sha.update(name.encode("utf-8"))
            for item in np.asarray(values[name]).ravel().tolist():
                if isinstance(item, str):
                    item = item.encode("utf-8")
                sha.update(item if isinstance(item, bytes) else repr(item).encode())
                sha.update(b"\0")
    elif isinstance(values, (bytes, str)):
        sha.update(values.encode("utf-8") if isinstance(values, str) else values)
    else:
        sha.update(np.ascontiguousarray(values).tobytes())
    return sha.hexdigest()


def attributes(obj):
    out = {}
    for name in sorted(obj.attrs.keys()):
        type_id = obj.attrs.get_id(name).get_type()
        value = obj.attrs[name]
        dtype = getattr(value, "dtype", np.asarray(value).dtype)
        out[name] = {
            "value": to_json(value),
            "type": describe_type(dtype, type_id),
        }
    return out


def describe(path, obj):
    node = {"path": path, "attrs": attributes(obj)}
    if isinstance(obj, h5py.Group):
        node["kind"] = "group"
    else:
        node["kind"] = "dataset"
        node["dtype"] = describe_type(obj.dtype, obj.id.get_type())
        # A null dataspace (the `null` encoding) has no shape and no values
        node["shape"] = None if obj.shape is None else list(obj.shape)
        node["digest"] = "empty" if obj.shape is None else digest(obj)
    return node


def tree(path):
    nodes = []
    with h5py.File(path, "r") as f:
        nodes.append(describe("/", f))
        f.visititems(lambda name, obj: nodes.append(describe("/" + name, obj)))
    nodes.sort(key=lambda n: n["path"])
    return nodes


def main(paths):
    # One file prints its list of nodes, several files print one list per file
    # (starting Python once for many files is much faster in the tests)
    if len(paths) == 1:
        print(json.dumps(tree(paths[0])))
    else:
        print(json.dumps([tree(path) for path in paths]))


if __name__ == "__main__":
    main(sys.argv[1:])
