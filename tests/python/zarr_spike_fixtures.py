"""Write zarr stores with the dtypes, codecs and layouts anndata uses.

Usage: zarr_spike_fixtures.py <outdir>

Writes one directory per zarr format (v2/ and v3/) holding `types.zarr`, a
group with one array per dtype, plus `layout.zarr` (chunking, sharding,
fill values, attributes), `anndata.zarr` (a small AnnData written by anndata
itself) and, for v3, `types.zarr.zip`.
Used by the zarr library spike tests (see `.scratch/zarr-io/zarr-spike.md`).
"""

import shutil
import sys
import warnings
from pathlib import Path

import anndata
import numcodecs
import numpy as np
import zarr

INT_DTYPES = ["int8", "int16", "int32", "int64", "uint8", "uint16", "uint32", "uint64"]
FLOAT_DTYPES = ["float32", "float64"]


def write_types(path, fmt):
    root = zarr.open_group(path, mode="w", zarr_format=fmt)
    for name in INT_DTYPES:
        root.create_array(name, data=np.arange(6, dtype=name).reshape(2, 3))
    for name in FLOAT_DTYPES:
        data = np.array([[0.5, -1.25, np.nan], [np.inf, 2.0, 3.5]], dtype=name)
        root.create_array(name, data=data)
    root.create_array("bool", data=np.array([[True, False, True], [False, False, True]]))
    strings = root.create_array("string", shape=(4,), dtype=str)
    strings[:] = np.array(["a", "bc", "", "ü€"], dtype=object)
    root.create_array("scalar_int", data=np.array(7, dtype="int64"))
    root.create_array("scalar_float", data=np.array(2.5, dtype="float64"))
    root.create_array("scalar_bool", data=np.array(True))
    scalar_string = root.create_array("scalar_string", shape=(), dtype=str)
    scalar_string[...] = "hi"
    root.attrs["str"] = "text"
    root.attrs["int"] = 3
    root.attrs["list"] = ["a", "b"]
    root.attrs["nested"] = {"k": [1, 2], "s": "v"}
    root["int32"].attrs["encoding-type"] = "array"
    root["int32"].attrs["encoding-version"] = "0.2.0"
    root["int32"].attrs["array_attr"] = [1, 2, 3]
    root["int32"].attrs["object_attr"] = {"a": 1, "b": ["x"]}
    zarr.consolidate_metadata(path)


def write_layout(path, fmt):
    root = zarr.open_group(path, mode="w", zarr_format=fmt)
    data = np.arange(40, dtype="float64").reshape(8, 5)
    root.create_array("chunked", data=data, chunks=(3, 2))
    root.create_array("c_order", data=np.arange(6, dtype="int32").reshape(2, 3), chunks=(2, 3))
    if fmt == 2:
        codecs = {
            "zstd": numcodecs.Zstd(level=3),
            "blosc": numcodecs.Blosc(),
            "gzip": numcodecs.GZip(),
        }
        for name, codec in codecs.items():
            root.create_array(name, data=data, chunks=(4, 5), compressors=codec)
    else:
        codecs = {
            "zstd": zarr.codecs.ZstdCodec(level=3),
            "blosc": zarr.codecs.BloscCodec(),
            "gzip": zarr.codecs.GzipCodec(),
        }
        for name, codec in codecs.items():
            root.create_array(name, data=data, chunks=(4, 5), compressors=codec)
    root.create_array("uncompressed", data=data, chunks=(4, 5), compressors=None)
    # missing chunks: only fill_value is stored
    missing = root.create_array("missing", shape=(4, 4), chunks=(2, 2), dtype="int32", fill_value=-1)
    missing[0:2, 0:2] = np.array([[1, 2], [3, 4]], dtype="int32")
    root.create_array("fill_nan", shape=(2, 2), chunks=(2, 2), dtype="float64", fill_value=np.nan)
    if fmt == 3:
        root.create_array(
            "sharded", data=data, chunks=(2, 5), shards=(4, 5), compressors=zarr.codecs.ZstdCodec()
        )
    zarr.consolidate_metadata(path)


def write_anndata(path, fmt):
    rng = np.random.default_rng(0)
    import pandas as pd
    import scipy.sparse as sp

    adata = anndata.AnnData(
        X=sp.random(6, 4, density=0.5, format="csr", dtype="float32", random_state=0),
        obs=pd.DataFrame(
            {"group": pd.Categorical(list("aabbcc")), "n": np.arange(6, dtype="int64")},
            index=[f"c{i}" for i in range(6)],
        ),
        var=pd.DataFrame(index=[f"g{i}" for i in range(4)]),
        layers={"counts": rng.integers(0, 5, (6, 4)).astype("int32")},
        uns={"title": "spike", "n": 3, "arr": np.arange(3)},
    )
    with anndata.settings.override(zarr_write_format=fmt):
        adata.write_zarr(path)


def main(outdir):
    outdir = Path(outdir)
    warnings.simplefilter("ignore")
    for fmt in (2, 3):
        sub = outdir / f"v{fmt}"
        if sub.exists():
            shutil.rmtree(sub)
        sub.mkdir(parents=True)
        write_types(sub / "types.zarr", fmt)
        write_layout(sub / "layout.zarr", fmt)
        write_anndata(sub / "anndata.zarr", fmt)
        with zarr.storage.ZipStore(sub / "types.zarr.zip", mode="w") as store:
            write_types(store, fmt)


if __name__ == "__main__":
    main(sys.argv[1])
