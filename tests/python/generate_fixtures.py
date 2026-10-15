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
