"""Print the exact member types, values and compression of a compound dataset.

Usage: compound_types.py <file> <dataset>

Prints JSON: `shape`, `compression` and `fields` (name, numpy dtype string,
and for strings the h5py encoding and length, with the values).
"""

import json
import sys

import h5py


def to_plain(item):
    if isinstance(item, bytes):
        return item.decode("utf-8")
    if hasattr(item, "item"):
        return to_plain(item.item())
    return item


def main(path, name):
    with h5py.File(path, "r") as f:
        dset = f[name]
        values = dset[()]
        fields = []
        for field in dset.dtype.names:
            dtype = dset.dtype[field]
            info = h5py.check_string_dtype(dtype)
            fields.append(
                {
                    "name": field,
                    "dtype": str(dtype),
                    "string": None
                    if info is None
                    else {"encoding": info.encoding, "length": info.length},
                    "enum": h5py.check_enum_dtype(dtype) is not None,
                    "values": [to_plain(v) for v in values[field].tolist()],
                }
            )
        print(
            json.dumps(
                {
                    "shape": list(dset.shape),
                    "compression": dset.compression,
                    "fields": fields,
                }
            )
        )


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
