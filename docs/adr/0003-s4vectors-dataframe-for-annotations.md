# obs and var are S4Vectors DataFrames

`obs` and `var` are stored as `S4Vectors::DataFrame` instead of base `data.frame` or tibble.
pandas indexes, which become obs_names and var_names, may contain duplicates (Python only warns), and base `data.frame` row names cannot, so base frames would make some valid files impossible to round trip.
`DataFrame` allows duplicate row names, holds any vector-like column type (useful for dtype-preserving column classes) and matches what Bioconductor single-cell users already know.
The cost is a Bioconductor dependency and slightly less familiar syntax for users who know only base R.
