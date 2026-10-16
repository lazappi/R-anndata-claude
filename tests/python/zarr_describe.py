"""Print one JSON line per node of a zarr store, as Python zarr sees it.

Usage: zarr_describe.py <store>

Output is one JSON object per array or group, keyed by path, with the zarr
format, dtype, shape, chunks, fill value, attributes and (for arrays) values as
plain JSON.
An array that Python cannot read gets an "error" instead of values.
Used by the zarr library spike tests to check what R wrote.
"""

import json
import sys
import warnings

import numpy as np
import zarr


def to_json(value):
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    if isinstance(value, np.ndarray):
        return [to_json(v) for v in value.tolist()]
    if isinstance(value, np.generic):
        return to_json(value.item())
    if isinstance(value, (list, tuple)):
        return [to_json(v) for v in value]
    if isinstance(value, dict):
        return {k: to_json(v) for k, v in value.items()}
    if isinstance(value, float) and not np.isfinite(value):
        return repr(value)
    return value


def describe(node, path):
    info = {"attrs": to_json(dict(node.attrs)), "format": node.metadata.zarr_format}
    if isinstance(node, zarr.Array):
        info.update(
            kind="array",
            dtype=str(node.dtype),
            shape=list(node.shape),
            chunks=list(node.chunks),
            fill_value=to_json(node.fill_value),
        )
        try:
            info["value"] = to_json(node[...])
        except Exception as e:  # noqa: BLE001 - report whatever Python says
            info["error"] = f"{type(e).__name__}: {e}"
    else:
        info["kind"] = "group"
    print(json.dumps({path: info}))


def main(store):
    warnings.simplefilter("ignore")
    root = zarr.open(store, mode="r")
    describe(root, "/")
    if isinstance(root, zarr.Group):
        for path, node in root.members(max_depth=None):
            describe(node, "/" + path)


if __name__ == "__main__":
    main(sys.argv[1])
