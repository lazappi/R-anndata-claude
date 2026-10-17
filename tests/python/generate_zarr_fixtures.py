"""Write the zarr counterparts of the encoding fixtures and a manifest.

Usage: generate_zarr_fixtures.py <outdir>

`<outdir>` is the zarr fixture directory (tests/testthat/fixtures/zarr). Every
case of generate_fixtures.py that has a zarr equivalent is written by Python
with its defaults as a v3 store (`v3/`, sharded) and a v2 store (`v2/`). A few
base cases are also written as v3 variants: unsharded, unconsolidated and one
per compressor.

Element cases hold their Element at the key "x" of a group (written with
`write_elem`, so the root only holds that Element and is not consolidated).
Whole-object cases are written with `write_zarr` (consolidated by default).
Cases that Python refuses to write are recorded under "errors" of the variant.
"""

import json
import shutil
import sys
import warnings
from importlib.metadata import version
from pathlib import Path

# `-I` removes the script directory from the path
sys.path.insert(0, str(Path(__file__).resolve().parent))

import anndata  # noqa: E402
import generate_fixtures as base  # noqa: E402
import zarr  # noqa: E402

# Cases with no zarr equivalent (a raw HDF5 `bytes` dataset) or that are only
# about HDF5 compression
SKIP = {"bytes_scalar", "realistic_gzip", "realistic_lzf"}

# Base cases that are also written in each variant
VARIANT_CASES = (
    "anndata_full",
    "realistic",
    "csr_float64",
    "array_float64_2d",
    "df_all_types",
    "string_array_1d",
    "rec_array_basic",
    "rec_array_widths",
)
WHOLE_OBJECT_VARIANT_CASES = ("anndata_full", "realistic")


def compressors():
    from zarr.codecs import BloscCodec, GzipCodec, ZstdCodec

    return {
        "zstd": ZstdCodec(level=3),
        "blosc": BloscCodec(),
        "gzip": GzipCodec(),
        "none": None,
    }


def _factories():
    """The Python value or AnnData factory of every case, by name."""
    elements = base._element_cases()
    values = dict(elements)
    for name, (source, settings) in base.SETTING_CASES.items():
        values[name] = (elements[source], settings)
    objects = dict(base._adata_cases())
    objects["realistic"] = lambda: base._realistic_adata("csr")
    objects["realistic_csc"] = lambda: base._realistic_adata("csc")
    return values, objects


def _write_element(path, value, fmt, settings, dataset_kwargs):
    from anndata.io import write_elem

    group = zarr.open_group(path, mode="w", zarr_format=fmt)
    with anndata.settings.override(**settings):
        write_elem(group, "x", value, dataset_kwargs=dataset_kwargs)
    return base._describe_value(value)


def _write_object(path, adata, fmt, settings, dataset_kwargs, consolidate):
    # The `AnnData.write_zarr` method takes no dataset arguments, the function does
    from anndata.io import write_zarr

    with anndata.settings.override(**settings):
        write_zarr(path, adata, consolidate_metadata=consolidate, **dataset_kwargs)


# name -> (zarr format, anndata settings, dataset kwargs, consolidate, cases)
def variants():
    out = {
        "v3": (3, {}, {}, True, None),
        "v2": (2, {}, {}, True, None),
        "v3_unsharded": (3, {"auto_shard_zarr_v3": False}, {}, True, VARIANT_CASES),
        "v3_unconsolidated": (3, {}, {}, False, WHOLE_OBJECT_VARIANT_CASES),
    }
    for name, codec in compressors().items():
        out[f"v3_{name}"] = (3, {}, {"compressors": codec}, True, VARIANT_CASES)
    return out


def write_case(path, name, fmt, settings, dataset_kwargs, consolidate, values, objects):
    settings = {"zarr_write_format": fmt, **settings}
    if name in objects:
        _write_object(path, objects[name](), fmt, settings, dataset_kwargs, consolidate)
        return None
    entry = values[name]
    if isinstance(entry, tuple):
        entry, extra = entry
        settings = {**settings, **extra}
    return _write_element(path, entry(), fmt, settings, dataset_kwargs)


def main(outdir):
    outdir = Path(outdir)
    warnings.simplefilter("ignore")
    values, objects = _factories()
    names = sorted((set(values) | set(objects)) - SKIP)
    manifest = {
        "versions": {
            name: version(name)
            for name in ("anndata", "zarr", "numcodecs", "numpy", "pandas")
        },
        "variants": {},
    }
    for variant, (fmt, settings, kwargs, consolidate, only) in variants().items():
        folder = outdir / variant
        if folder.exists():
            shutil.rmtree(folder)
        folder.mkdir(parents=True)
        record = {"format": fmt, "cases": {}, "errors": {}}
        for name in names if only is None else only:
            path = folder / f"{name}.zarr"
            try:
                python = write_case(
                    path, name, fmt, settings, kwargs, consolidate, values, objects
                )
            except Exception as err:  # noqa: BLE001 - Python's refusal is the data
                shutil.rmtree(path, ignore_errors=True)
                record["errors"][name] = {
                    "type": type(err).__name__,
                    "message": str(err).splitlines()[0] if str(err) else "",
                }
                continue
            record["cases"][name] = {"file": f"{variant}/{name}.zarr"}
            if python is not None:
                record["cases"][name]["python"] = python
        manifest["variants"][variant] = record
    with open(outdir / "manifest.json", "w") as f:
        json.dump(manifest, f, indent=2, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1])
