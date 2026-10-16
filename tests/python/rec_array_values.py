"""Print the field names and values of a rec-array dataset as JSON.

Usage: rec_array_values.py <file> <dataset>

Used to compare rec-arrays by field names, order and values only, because R
cannot keep field dtypes (ADR 0005).
"""

import json
import sys

import h5py
import numpy as np


def to_plain(item):
    if isinstance(item, bytes):
        return item.decode("utf-8")
    if isinstance(item, np.generic):
        return to_plain(item.item())
    if isinstance(item, bool):
        return int(item)
    return item


def main(path, name):
    with h5py.File(path, "r") as f:
        values = f[name][()]
    fields = {
        field: [to_plain(item) for item in values[field].tolist()]
        for field in values.dtype.names
    }
    print(json.dumps({"names": list(values.dtype.names), "fields": fields}))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
