# AnnData is an R6 class with reference semantics

The `AnnData` object is an R6 class, so it is mutable and modified in place like the Python object, rather than following R's usual copy-on-modify semantics.
This was chosen over S4 and S7 because views, backed mode (an open file handle) and in-place modification of slots such as `adata$obs` map directly from Python, which keeps behaviour faithful and porting simple.
The cost is that `b <- a` creates an alias and not a copy, so users must call `a$copy()` as they would in Python.
