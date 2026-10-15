"""Print the observed rows of the encoding table as Markdown.

Usage: encoding_table.py <fixtures dir>

Reads the manifest and the files written by generate_fixtures.py, so every row
is observed from the Python reference, never assumed. Element cases hold their
Element at the key "x", whole-object cases (.h5ad) are described from the root.
"""

import json
import sys
from pathlib import Path

import h5py
import numpy as np

SKIP_ATTRS = {"encoding-type", "encoding-version"}


def dtype_text(ds):
    info = h5py.check_string_dtype(ds.dtype)
    if info is not None:
        kind = "variable" if info.length is None else f"fixed {info.length}"
        return f"string({kind}, {info.encoding})"
    tid = ds.id.get_type()
    if isinstance(tid, h5py.h5t.TypeEnumID):
        # h5py reads its enum as numpy bool, so read the members from the type
        members = ", ".join(
            f"{tid.get_member_name(i).decode()}={tid.get_member_value(i)}"
            for i in range(tid.get_nmembers())
        )
        return f"bool (enum int8: {members})"
    if ds.dtype.kind == "c":
        # h5py stores complex numbers as a compound of two floats
        tid = ds.id.get_type()
        names = [tid.get_member_name(i).decode() for i in range(tid.get_nmembers())]
        return f"{ds.dtype} (compound {', '.join(names)} of {ds.dtype.itemsize // 2}-byte floats)"
    if ds.dtype.names:
        fields = []
        for name in ds.dtype.names:
            sub = ds.dtype.fields[name][0]
            sub_info = h5py.check_string_dtype(sub)
            if sub_info is not None:
                kind = "vlen" if sub_info.length is None else f"S{sub_info.length}"
                fields.append(f"{name}:{kind}-{sub_info.encoding}")
            elif h5py.check_enum_dtype(sub) is not None:
                fields.append(f"{name}:bool")
            else:
                fields.append(f"{name}:{sub}")
        return "compound(" + ", ".join(fields) + ")"
    return str(ds.dtype)


def attr_text(obj):
    parts = []
    for key in sorted(obj.attrs):
        if key in SKIP_ATTRS:
            continue
        value = obj.attrs[key]
        stored = obj.attrs.get_id(key).dtype
        if isinstance(value, np.ndarray):
            value = value.tolist()
        elif isinstance(value, np.generic):
            value = value.item()
        if h5py.check_string_dtype(stored) is not None:
            kind = "str"
        elif h5py.check_enum_dtype(stored) is not None:
            kind = "bool"
        else:
            kind = str(stored)
        parts.append(f"{key}={value!r} ({kind})")
    return "; ".join(parts)


def encoding(obj):
    kind = obj.attrs.get("encoding-type", "(none)")
    version = obj.attrs.get("encoding-version", "")
    return f"{kind} {version}".strip()


def values_text(ds):
    """The values of a small dataset, so codes and masks are visible."""
    if ds.shape is None or ds.size > 6 or ds.dtype.names:
        return ""
    items = np.atleast_1d(ds[()]).ravel().tolist()
    items = [i.decode("utf-8") if isinstance(i, bytes) else i for i in items]
    return f" = {items}"


def describe(obj, depth=0):
    """Describe a node, `depth` 0 is the Element itself and 1 a whole object's Slots."""
    if isinstance(obj, h5py.Dataset):
        if obj.shape is None:
            shape = "null dataspace"
        elif obj.shape == ():
            shape = "scalar"
        else:
            shape = "x".join(map(str, obj.shape))
        comp = f", {obj.compression}" if obj.compression else ""
        return f"{encoding(obj)}: {dtype_text(obj)} [{shape}]{comp}{values_text(obj)}"
    if depth >= 2:
        return encoding(obj)
    items = []
    for name, child in obj.items():
        text = describe(child, depth + 1)
        if isinstance(child, h5py.Group) and depth == 0:
            extra = attr_text(child)
            text = encoding(child) + (f" ({extra})" if extra else "") + " " + text
        items.append(f"{name}: {text}")
    return "{" + "; ".join(items) + "}"


def escape(text):
    return str(text).replace("|", "\\|")


START = "<!-- observed:start -->"
END = "<!-- observed:end -->"


def main(directory, doc):
    """Replace the observed table between the markers in `doc`."""
    directory = Path(directory)
    manifest = json.loads((directory / "manifest.json").read_text())
    lines = [
        "| Case | Python value | Encoding | On disk | Other attributes |",
        "| ---- | ------------ | -------- | ------- | ---------------- |",
    ]
    for name, entry in sorted(manifest["cases"].items()):
        if not entry["file"].startswith("h5ad/"):
            continue
        with h5py.File(directory / entry["file"], "r") as f:
            node = f["x"] if "x" in f else f
            # Whole objects only list their Slots, the detail is in the element cases
            depth = 0 if "x" in f else 1
            row = [
                f"`{name}`",
                entry.get("python", ""),
                encoding(node),
                describe(node, depth),
                attr_text(node),
            ]
        lines.append("| " + " | ".join(escape(c) for c in row) + " |")
    for name, err in sorted(manifest["errors"].items()):
        row = [f"`{name}`", "", "Python error", err["type"], err["message"]]
        lines.append("| " + " | ".join(escape(c) for c in row) + " |")

    text = Path(doc).read_text()
    head, rest = text.split(START)
    tail = rest.split(END)[1]
    Path(doc).write_text(head + START + "\n" + "\n".join(lines) + "\n" + END + tail)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
