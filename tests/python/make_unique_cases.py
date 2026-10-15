"""Write Python's make_index_unique results for fixed cases as JSON.

Usage: make_unique_cases.py OUTPUT.json
"""

import json
import sys
import warnings

import pandas as pd
from anndata.utils import make_index_unique

CASES = {
    "unique": (["a", "b", "c"], "-"),
    "simple_duplicates": (["a", "a", "b", "a"], "-"),
    "custom_join": (["a", "a", "b", "b", "b"], "_"),
    "empty_join": (["a", "a", "a"], ""),
    "collision": (["a", "a", "a-1"], "-"),
    "collision_chain": (["a", "a", "a", "a-1", "a-2"], "-"),
    "many_collisions": (
        ["a"] * 8 + [f"a-{i}" for i in range(1, 8)],
        "-",
    ),
    "na_ignored": (["a", None, "a", None, "b"], "-"),
    "only_na": ([None, None], "-"),
    "na_unique": (["a", None, "b"], "-"),
}


def run(names, join):
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        result = make_index_unique(pd.Index(names, dtype=object), join)
    return {
        "names": names,
        "join": join,
        "result": [None if pd.isna(x) else x for x in result],
        "warnings": [str(w.message) for w in caught],
    }


if __name__ == "__main__":
    out = {name: run(*args) for name, args in CASES.items()}
    with open(sys.argv[1], "w") as f:
        json.dump(out, f, indent=2)
        f.write("\n")
