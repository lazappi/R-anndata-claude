"""Write the committed test fixtures and a manifest describing them.

Usage: generate_fixtures.py <outdir>

Cases are registered with the `case` decorator. Each case function takes the
output path and writes one file. Output must be deterministic (fixed seeds, no
timestamps in the content that tests compare). The manifest lists each case,
its file and the reference versions used.
"""

import json
import sys
from importlib.metadata import version
from pathlib import Path

import anndata
import numpy as np

CASES = {}


def case(filename):
    """Register a function that writes the fixture `filename` under its name."""

    def register(fn):
        CASES[fn.__name__] = {"file": filename, "write": fn}
        return fn

    return register


@case("trivial.h5ad")
def trivial(path):
    """A tiny dense float32 matrix with default names."""
    anndata.AnnData(np.arange(6, dtype=np.float32).reshape(2, 3)).write_h5ad(path)


@case("spike_types.h5")
def spike_types(path):
    """Low-level HDF5 types the h5ad-io spike checks rhdf5 against."""
    import h5py

    str_dt = h5py.string_dtype()
    with h5py.File(path, "w") as f:
        f.create_dataset(
            "vlen_utf8",
            data=np.array(["a", "bé", "", "日本"], dtype=object),
            dtype=str_dt,
        )
        f.create_dataset(
            "vlen_utf8_2d",
            data=np.array([["a", "b", "c"], ["d", "e", "f"]], dtype=object),
            dtype=str_dt,
        )
        f.create_dataset("bool", data=np.array([True, False, True]))
        f.create_dataset(
            "bool_2d", data=np.array([[True, False, True], [False, False, True]])
        )
        for name in (
            "int8",
            "int16",
            "int32",
            "int64",
            "uint8",
            "uint16",
            "uint32",
            "uint64",
        ):
            info = np.iinfo(name)
            # 64-bit extremes are not representable as doubles, so the exact
            # R-readable boundary (2^53) is used and the hazards are separate
            lo, hi = max(info.min, -(2**53)), min(info.max, 2**53)
            f.create_dataset(name, data=np.array([lo, 0, 1, hi], dtype=name))
        f.create_dataset(
            "int64_big", data=np.array([2**53 + 1, -(2**62)], dtype="int64")
        )
        f.create_dataset(
            "uint64_big", data=np.array([2**63 + 5, 2**64 - 1], dtype="uint64")
        )
        special = [1.5, -2.25, np.nan, np.inf]
        f.create_dataset("float32", data=np.array(special, dtype="float32"))
        f.create_dataset("float64", data=np.array(special, dtype="float64"))
        z = [1 + 2j, -3.5 + 0.25j]
        f.create_dataset("complex64", data=np.array(z, dtype="complex64"))
        f.create_dataset("complex128", data=np.array(z, dtype="complex128"))
        f.create_dataset("matrix_2x3", data=np.arange(6, dtype="int32").reshape(2, 3))
        f.create_dataset(
            "array_2x3x4", data=np.arange(24, dtype="float64").reshape(2, 3, 4)
        )
        f.create_dataset("scalar_int", data=np.int32(7))
        f.create_dataset("scalar_float", data=np.float64(2.5))
        f.create_dataset("scalar_str", data="héllo", dtype=str_dt)
        f.create_dataset("scalar_bool", data=np.bool_(True))
        rec = np.array(
            [(1, 1.5, b"ab", "x"), (2, 2.5, b"c", "yé")],
            dtype=[("i", "<i4"), ("f", "<f8"), ("fixed", "S3"), ("v", str_dt)],
        )
        f.create_dataset("rec", data=rec)
        widths = np.array(
            [(1, -2, 3, 4, 0.5, True), (255, 7, 4000000000, -9, 1.5, False)],
            dtype=[
                ("u1", "u1"),
                ("i2", "<i2"),
                ("u4", "<u4"),
                ("i8", "<i8"),
                ("f4", "<f4"),
                ("b", "?"),
            ],
        )
        f.create_dataset("rec_widths", data=widths)
        big = np.arange(1000, dtype="float64").reshape(10, 100)
        f.create_dataset(
            "gzip", data=big, compression="gzip", compression_opts=4, chunks=(5, 50)
        )
        f.create_dataset("lzf", data=big, compression="lzf", chunks=(5, 50))
        g = f.create_group("attrs")
        g.attrs["str"] = "héllo"
        g.attrs["str_array"] = np.array(["a", "b", "c"], dtype=object)
        g.attrs["int"] = np.int64(5)
        g.attrs["float"] = np.float64(0.5)
        g.attrs["int_array"] = np.array([1, 2, 3], dtype="int32")
        g.attrs["bool"] = np.bool_(True)
        g.attrs["shape"] = np.array([2, 3], dtype="int64")


def main(outdir):
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    manifest = {
        "versions": {
            name: version(name) for name in ("anndata", "h5py", "numpy", "pandas")
        },
        "cases": {},
    }
    for name, entry in sorted(CASES.items()):
        entry["write"](outdir / entry["file"])
        manifest["cases"][name] = {"file": entry["file"]}
    with open(outdir / "manifest.json", "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1])
