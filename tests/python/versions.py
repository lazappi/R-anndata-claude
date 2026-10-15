"""Print the anndata and pandas versions as JSON."""

import json

import anndata
import pandas

print(json.dumps({"anndata": anndata.__version__, "pandas": pandas.__version__}))
