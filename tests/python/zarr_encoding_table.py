"""Replace the observed rows of the zarr encoding table with the fixtures'.

Usage: zarr_encoding_table.py <zarr fixtures dir> <doc>

Reads the manifest and the v3 and v2 stores written by generate_zarr_fixtures.py
and describes them from the metadata files themselves (`zarr.json` in v3,
`.zgroup`, `.zarray` and `.zattrs` in v2), so every row is what Python wrote,
never an assumption. Element cases hold their Element at the key "x",
whole-object cases are described from the root.
"""

import json
import sys
from pathlib import Path

SKIP_ATTRS = {"encoding-type", "encoding-version"}
START = "<!-- observed:start -->"
END = "<!-- observed:end -->"


def load(path):
    return json.loads(path.read_text())


def read_node(directory):
    """Metadata of a node as (kind, metadata, attributes), for either version."""
    if (directory / "zarr.json").exists():
        meta = load(directory / "zarr.json")
        return meta["node_type"], meta, meta.get("attributes", {})
    attrs_file = directory / ".zattrs"
    attrs = load(attrs_file) if attrs_file.exists() else {}
    if (directory / ".zarray").exists():
        return "array", load(directory / ".zarray"), attrs
    return "group", load(directory / ".zgroup"), attrs


def compact(value):
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)


def codec_text(codec):
    name = codec["name"] if "name" in codec else codec["id"]
    config = codec.get("configuration") or {
        k: v for k, v in codec.items() if k not in ("id", "name")
    }
    if name == "sharding_indexed":
        inner = ", ".join(codec_text(c) for c in config["codecs"])
        index = ", ".join(codec_text(c) for c in config["index_codecs"])
        chunk = "x".join(map(str, config["chunk_shape"]))
        return f"sharding(inner chunks {chunk}; {inner}; index {index})"
    config = {k: v for k, v in config.items() if k != "endian"}
    return f"{name}({compact(config)})" if config else name


def array_text(version, meta):
    shape = "x".join(map(str, meta["shape"])) or "scalar"
    if version == 3:
        grid = meta["chunk_grid"]["configuration"]["chunk_shape"]
        codecs = ", ".join(codec_text(c) for c in meta["codecs"])
        dtype = meta["data_type"]
        dtype = dtype if isinstance(dtype, str) else compact(dtype)
        layout = f"chunks {'x'.join(map(str, grid)) or 'none'}"
        return f"{dtype} [{shape}] {layout}; codecs {codecs}; fill {compact(meta['fill_value'])}"
    filters = ", ".join(codec_text(c) for c in meta["filters"] or []) or "none"
    compressor = codec_text(meta["compressor"]) if meta["compressor"] else "none"
    layout = f"chunks {'x'.join(map(str, meta['chunks'])) or 'none'}; order {meta['order']}"
    dtype = meta["dtype"] if isinstance(meta["dtype"], str) else compact(meta["dtype"])
    return (
        f"{dtype} [{shape}] {layout}; compressor {compressor}; filters {filters}; "
        f"fill {compact(meta['fill_value'])}"
    )


def encoding(attrs):
    kind = attrs.get("encoding-type", "(none)")
    return f"{kind} {attrs.get('encoding-version', '')}".strip()


def attr_text(attrs):
    return "; ".join(
        f"{key}={compact(value)}"
        for key, value in sorted(attrs.items())
        if key not in SKIP_ATTRS
    )


def describe(directory, version, depth=0):
    """Describe a node, `depth` 0 is the Element itself and 1 a whole object's Slots."""
    kind, meta, attrs = read_node(directory)
    if kind == "array":
        return f"{encoding(attrs)}: {array_text(version, meta)}"
    if depth >= 2:
        return encoding(attrs)
    items = []
    for child in sorted(p for p in directory.iterdir() if p.is_dir()):
        text = describe(child, version, depth + 1)
        if depth == 0:
            _, _, child_attrs = read_node(child)
            extra = attr_text(child_attrs)
            if read_node(child)[0] == "group":
                text = encoding(child_attrs) + (f" ({extra})" if extra else "") + " " + text
        items.append(f"{child.name}: {text}")
    return "{" + "; ".join(items) + "}"


def escape(text):
    return str(text).replace("|", "\\|")


def main(directory, doc):
    """Replace the observed table between the markers in `doc`."""
    directory = Path(directory)
    manifest = load(directory / "manifest.json")
    lines = [
        "| Case | Zarr | Python value | Encoding | On disk | Other attributes |",
        "| ---- | ---- | ------------ | -------- | ------- | ---------------- |",
    ]
    names = sorted(manifest["variants"]["v3"]["cases"] | manifest["variants"]["v3"]["errors"])
    for name in names:
        for variant in ("v3", "v2"):
            record = manifest["variants"][variant]
            if name in record["errors"]:
                err = record["errors"][name]
                row = [f"`{name}`", variant, "", "Python error", err["type"], err["message"]]
            else:
                entry = record["cases"][name]
                store = directory / entry["file"]
                # Only Elements record a Python value (and the file system may
                # not tell `x` from `X`)
                is_element = "python" in entry
                node = store / "x" if is_element else store
                _, _, attrs = read_node(node)
                row = [
                    f"`{name}`",
                    variant,
                    entry.get("python", ""),
                    encoding(attrs),
                    describe(node, record["format"], 0 if is_element else 1),
                    attr_text(attrs),
                ]
            lines.append("| " + " | ".join(escape(c) for c in row) + " |")

    text = Path(doc).read_text()
    head, rest = text.split(START)
    tail = rest.split(END)[1]
    Path(doc).write_text(head + START + "\n" + "\n".join(lines) + "\n" + END + tail)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
