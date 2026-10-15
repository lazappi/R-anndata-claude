"""Print one JSON line per dataset and attribute of an HDF5 file, as h5py sees it.

Usage: spike_describe.py <file>

Output is a JSON object keyed by "path" (datasets) or "path@attr" (attributes),
each with the h5py dtype description, shape and values as plain JSON.
Used by the rhdf5 spike tests to check what R wrote.
"""

import json
import sys

import h5py
import numpy as np


def describe_dtype(dtype, type_id):
    info = h5py.check_string_dtype(dtype)
    if info is not None:
        if info.length is None:
            return f"string(variable, {info.encoding})"
        return f"string(fixed {info.length}, {info.encoding})"
    if h5py.check_enum_dtype(dtype) is not None:
        return f"enum({dtype.str}, {h5py.check_enum_dtype(dtype)})"
    if dtype.names is not None:
        fields = []
        for name in dtype.names:
            sub = dtype.fields[name][0]
            sub_info = h5py.check_string_dtype(sub)
            if sub_info is not None:
                kind = "variable" if sub_info.length is None else f"fixed {sub_info.length}"
                fields.append(f"{name}:string({kind}, {sub_info.encoding})")
            else:
                fields.append(f"{name}:{sub}")
        return "compound(" + ", ".join(fields) + ")"
    return str(dtype)


def to_json(value):
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
    if isinstance(value, complex):
        return [value.real, value.imag]
    return value


def main(path):
    out = {}
    with h5py.File(path, "r") as f:

        def visit(name, obj):
            for attr in obj.attrs:
                type_id = obj.attrs.get_id(attr).get_type()
                value = obj.attrs[attr]
                dtype = getattr(value, "dtype", np.asarray(value).dtype)
                out[f"/{name}@{attr}"] = {
                    "dtype": describe_dtype(dtype, type_id),
                    "shape": list(getattr(value, "shape", ())),
                    "value": to_json(value),
                }
            if isinstance(obj, h5py.Dataset):
                out["/" + name] = {
                    "dtype": describe_dtype(obj.dtype, obj.id.get_type()),
                    "shape": list(obj.shape),
                    "value": to_json(obj[()]),
                    "compression": obj.compression,
                    "compression_opts": to_json(obj.compression_opts),
                }

        f.visititems(visit)
    for key in sorted(out):
        print(json.dumps({key: out[key]}))


if __name__ == "__main__":
    main(sys.argv[1])
